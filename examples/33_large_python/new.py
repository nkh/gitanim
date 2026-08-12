#!/usr/bin/env python3
"""Refactored blog service using SQLAlchemy models with connection pooling,
proper error handling, and structured logging."""

from __future__ import annotations

import logging
import os
from contextlib import contextmanager
from datetime import datetime
from typing import Iterator, List, Optional, Dict, Any

from flask import Flask, request, jsonify, Blueprint
from sqlalchemy import (
    Column, Integer, Text, DateTime, ForeignKey, create_engine, select,
    func, and_, String,
)
from sqlalchemy.exc import SQLAlchemyError, IntegrityError, NoResultFound
from sqlalchemy.orm import (
    declarative_base, sessionmaker, Session, relationship, scoped_session,
)

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

class Config:
    DATABASE_URL: str = os.environ.get(
        'DATABASE_URL', 'sqlite:///blog.db'
    )
    POOL_SIZE: int = int(os.environ.get('DB_POOL_SIZE', '5'))
    MAX_OVERFLOW: int = int(os.environ.get('DB_MAX_OVERFLOW', '10'))
    POOL_RECYCLE: int = int(os.environ.get('DB_POOL_RECYCLE', '1800'))
    ECHO_SQL: bool = os.environ.get('DB_ECHO', '0').startswith('1')


config = Config()

# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

engine = create_engine(
    config.DATABASE_URL,
    pool_size=config.POOL_SIZE,
    max_overflow=config.MAX_OVERFLOW,
    pool_recycle=config.POOL_RECYCLE,
    echo=config.ECHO_SQL,
    future=True,
)

SessionFactory = sessionmaker(bind=engine, expire_on_commit=False, future=True)
db_session = scoped_session(SessionFactory)

Base = declarative_base()


@contextmanager
def session_scope() -> Iterator[Session]:
    """Provide a transactional scope around a series of operations."""
    session = db_session()
    try:
        yield session
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        log.warning("integrity error: %s", exc)
        raise ValidationError("constraint violation") from exc
    except SQLAlchemyError as exc:
        session.rollback()
        log.exception("database error")
        raise DatabaseError(str(exc)) from exc
    finally:
        db_session.remove()


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class Post(Base):
    __tablename__ = 'posts'

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String(256), nullable=False)
    body = Column(Text, nullable=False)
    author = Column(String(128), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    comments = relationship(
        'Comment', back_populates='post',
        cascade='all, delete-orphan',
    )

    def to_dict(self, include_comments: bool = False) -> Dict[str, Any]:
        data = {
            'id': self.id,
            'title': self.title,
            'body': self.body,
            'author': self.author,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
        if include_comments:
            data['comments'] = [c.to_dict() for c in self.comments]
        return data


class Comment(Base):
    __tablename__ = 'comments'

    id = Column(Integer, primary_key=True, autoincrement=True)
    post_id = Column(Integer, ForeignKey('posts.id', ondelete='CASCADE'), nullable=False)
    author = Column(String(128), nullable=False)
    body = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    post = relationship('Post', back_populates='comments')

    def to_dict(self) -> Dict[str, Any]:
        return {
            'id': self.id,
            'post_id': self.post_id,
            'author': self.author,
            'body': self.body,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


# ---------------------------------------------------------------------------
# Custom exceptions
# ---------------------------------------------------------------------------

class BlogError(Exception):
    """Base exception for blog errors."""
    status_code: int = 500


class NotFoundError(BlogError):
    status_code = 404


class ValidationError(BlogError):
    status_code = 400


class DatabaseError(BlogError):
    status_code = 503


# ---------------------------------------------------------------------------
# Service layer
# ---------------------------------------------------------------------------

class PostService:
    """Encapsulates business logic for post operations."""

    @staticmethod
    def list_posts(limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        with session_scope() as session:
            stmt = (
                select(Post)
                .order_by(Post.created_at.desc())
                .limit(limit)
                .offset(offset)
            )
            rows = session.execute(stmt).scalars().all()
            return [p.to_dict() for p in rows]

    @staticmethod
    def get_post(post_id: int) -> Dict[str, Any]:
        with session_scope() as session:
            stmt = select(Post).where(Post.id == post_id)
            post = session.execute(stmt).scalar_one_or_none()
            if post is None:
                raise NotFoundError(f"Post {post_id} not found")
            return post.to_dict(include_comments=True)

    @staticmethod
    def create_post(title: str, body: str, author: str) -> Dict[str, Any]:
        if not title or len(title) > 256:
            raise ValidationError("invalid title")
        if not body:
            raise ValidationError("body is required")
        if not author:
            raise ValidationError("author is required")
        with session_scope() as session:
            post = Post(title=title, body=body, author=author)
            session.add(post)
            session.flush()
            return post.to_dict()

    @staticmethod
    def update_post(post_id: int, title: Optional[str] = None,
                    body: Optional[str] = None) -> Dict[str, Any]:
        with session_scope() as session:
            stmt = select(Post).where(Post.id == post_id)
            post = session.execute(stmt).scalar_one_or_none()
            if post is None:
                raise NotFoundError(f"Post {post_id} not found")
            if title is not None:
                if len(title) > 256:
                    raise ValidationError("title too long")
                post.title = title
            if body is not None:
                post.body = body
            session.flush()
            return post.to_dict()

    @staticmethod
    def delete_post(post_id: int) -> None:
        with session_scope() as session:
            stmt = select(Post).where(Post.id == post_id)
            post = session.execute(stmt).scalar_one_or_none()
            if post is None:
                raise NotFoundError(f"Post {post_id} not found")
            session.delete(post)

    @staticmethod
    def search(query: str) -> List[Dict[str, Any]]:
        if not query or len(query) < 2:
            raise ValidationError("query must be at least 2 characters")
        with session_scope() as session:
            pattern = f'%{query}%'
            stmt = (
                select(Post)
                .where(Post.title.like(pattern) | Post.body.like(pattern))
                .order_by(Post.created_at.desc())
            )
            rows = session.execute(stmt).scalars().all()
            return [p.to_dict() for p in rows]

    @staticmethod
    def list_authors() -> List[str]:
        with session_scope() as session:
            stmt = select(Post.author).distinct().order_by(Post.author)
            return [r for (r,) in session.execute(stmt).all()]


class CommentService:
    """Encapsulates business logic for comment operations."""

    @staticmethod
    def add_comment(post_id: int, author: str, body: str) -> Dict[str, Any]:
        if not author or not body:
            raise ValidationError("author and body are required")
        with session_scope() as session:
            # Ensure the post exists first.
            exists = session.execute(
                select(Post.id).where(Post.id == post_id)
            ).first()
            if exists is None:
                raise NotFoundError(f"Post {post_id} not found")
            comment = Comment(post_id=post_id, author=author, body=body)
            session.add(comment)
            session.flush()
            return comment.to_dict()

    @staticmethod
    def delete_comment(post_id: int, comment_id: int) -> None:
        with session_scope() as session:
            stmt = select(Comment).where(
                and_(Comment.id == comment_id, Comment.post_id == post_id)
            )
            comment = session.execute(stmt).scalar_one_or_none()
            if comment is None:
                raise NotFoundError(f"Comment {comment_id} not found")
            session.delete(comment)


# ---------------------------------------------------------------------------
# HTTP blueprint
# ---------------------------------------------------------------------------

api = Blueprint('api', __name__, url_prefix='')


@api.route('/posts', methods=['GET'])
def list_posts():
    limit = request.args.get('limit', 50, type=int)
    offset = request.args.get('offset', 0, type=int)
    return jsonify(PostService.list_posts(limit=limit, offset=offset))


@api.route('/posts/<int:post_id>', methods=['GET'])
def get_post(post_id: int):
    return jsonify(PostService.get_post(post_id))


@api.route('/posts', methods=['POST'])
def create_post():
    data = request.get_json() or {}
    return jsonify(PostService.create_post(
        title=data.get('title', ''),
        body=data.get('body', ''),
        author=data.get('author', ''),
    )), 201


@api.route('/posts/<int:post_id>', methods=['PUT'])
def update_post(post_id: int):
    data = request.get_json() or {}
    return jsonify(PostService.update_post(
        post_id=post_id,
        title=data.get('title'),
        body=data.get('body'),
    ))


@api.route('/posts/<int:post_id>', methods=['DELETE'])
def delete_post(post_id: int):
    PostService.delete_post(post_id)
    return jsonify({'status': 'ok'})


@api.route('/posts/<int:post_id>/comments', methods=['POST'])
def add_comment(post_id: int):
    data = request.get_json() or {}
    return jsonify(CommentService.add_comment(
        post_id=post_id,
        author=data.get('author', ''),
        body=data.get('body', ''),
    )), 201


@api.route('/posts/<int:post_id>/comments/<int:comment_id>', methods=['DELETE'])
def delete_comment(post_id: int, comment_id: int):
    CommentService.delete_comment(post_id, comment_id)
    return jsonify({'status': 'ok'})


@api.route('/authors', methods=['GET'])
def list_authors():
    return jsonify(PostService.list_authors())


@api.route('/authors/<author>/posts', methods=['GET'])
def posts_by_author(author: str):
    with session_scope() as session:
        stmt = (
            select(Post)
            .where(Post.author == author)
            .order_by(Post.created_at.desc())
        )
        rows = session.execute(stmt).scalars().all()
        return jsonify([p.to_dict() for p in rows])


@api.route('/search', methods=['GET'])
def search_posts():
    q = request.args.get('q', '')
    return jsonify(PostService.search(q))


# ---------------------------------------------------------------------------
# Application factory
# ---------------------------------------------------------------------------

def create_app() -> Flask:
    app = Flask(__name__)
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s %(levelname)s %(name)s %(message)s',
    )

    @app.errorhandler(BlogError)
    def handle_blog_error(exc: BlogError):
        log.info("blog error: %s", exc)
        return jsonify({'error': str(exc)}), exc.status_code

    @app.errorhandler(404)
    def handle_not_found(exc):
        return jsonify({'error': 'not found'}), 404

    @app.errorhandler(500)
    def handle_server_error(exc):
        log.exception("unhandled error")
        return jsonify({'error': 'internal server error'}), 500

    app.register_blueprint(api)

    @app.teardown_appcontext
    def shutdown_session(exception=None):
        db_session.remove()

    Base.metadata.create_all(engine)
    return app


if __name__ == '__main__':
    app = create_app()
    app.run(debug=True, port=5000)
