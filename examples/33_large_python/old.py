#!/usr/bin/env python3
"""Simple Flask app with inline SQL queries for a blog."""

import sqlite3
from flask import Flask, request, jsonify, g

app = Flask(__name__)
DATABASE = 'blog.db'


def get_db():
    db = getattr(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
    return db


@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()


def init_db():
    db = get_db()
    db.executescript('''
        CREATE TABLE IF NOT EXISTS posts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            author TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS comments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            post_id INTEGER NOT NULL,
            author TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (post_id) REFERENCES posts (id)
        );
    ''')
    db.commit()


@app.route('/posts', methods=['GET'])
def list_posts():
    db = get_db()
    cur = db.execute('SELECT * FROM posts ORDER BY created_at DESC')
    posts = [dict(row) for row in cur.fetchall()]
    return jsonify(posts)


@app.route('/posts/<int:post_id>', methods=['GET'])
def get_post(post_id):
    db = get_db()
    cur = db.execute('SELECT * FROM posts WHERE id = ?', (post_id,))
    row = cur.fetchone()
    if row is None:
        return jsonify({'error': 'Post not found'}), 404
    post = dict(row)
    cur = db.execute('SELECT * FROM comments WHERE post_id = ?', (post_id,))
    post['comments'] = [dict(r) for r in cur.fetchall()]
    return jsonify(post)


@app.route('/posts', methods=['POST'])
def create_post():
    data = request.get_json()
    db = get_db()
    cur = db.execute(
        'INSERT INTO posts (title, body, author) VALUES (?, ?, ?)',
        (data['title'], data['body'], data['author'])
    )
    db.commit()
    return jsonify({'id': cur.lastrowid}), 201


@app.route('/posts/<int:post_id>', methods=['PUT'])
def update_post(post_id):
    data = request.get_json()
    db = get_db()
    db.execute(
        'UPDATE posts SET title = ?, body = ? WHERE id = ?',
        (data['title'], data['body'], post_id)
    )
    db.commit()
    return jsonify({'status': 'ok'})


@app.route('/posts/<int:post_id>', methods=['DELETE'])
def delete_post(post_id):
    db = get_db()
    db.execute('DELETE FROM posts WHERE id = ?', (post_id,))
    db.execute('DELETE FROM comments WHERE post_id = ?', (post_id,))
    db.commit()
    return jsonify({'status': 'ok'})


@app.route('/posts/<int:post_id>/comments', methods=['POST'])
def add_comment(post_id):
    data = request.get_json()
    db = get_db()
    cur = db.execute(
        'INSERT INTO comments (post_id, author, body) VALUES (?, ?, ?)',
        (post_id, data['author'], data['body'])
    )
    db.commit()
    return jsonify({'id': cur.lastrowid}), 201


@app.route('/posts/<int:post_id>/comments/<int:comment_id>', methods=['DELETE'])
def delete_comment(post_id, comment_id):
    db = get_db()
    db.execute(
        'DELETE FROM comments WHERE id = ? AND post_id = ?',
        (comment_id, post_id)
    )
    db.commit()
    return jsonify({'status': 'ok'})


@app.route('/authors', methods=['GET'])
def list_authors():
    db = get_db()
    cur = db.execute('SELECT DISTINCT author FROM posts ORDER BY author')
    authors = [row['author'] for row in cur.fetchall()]
    return jsonify(authors)


@app.route('/authors/<author>/posts', methods=['GET'])
def posts_by_author(author):
    db = get_db()
    cur = db.execute(
        'SELECT * FROM posts WHERE author = ? ORDER BY created_at DESC',
        (author,)
    )
    posts = [dict(row) for row in cur.fetchall()]
    return jsonify(posts)


@app.route('/search', methods=['GET'])
def search_posts():
    q = request.args.get('q', '')
    db = get_db()
    cur = db.execute(
        'SELECT * FROM posts WHERE title LIKE ? OR body LIKE ? ORDER BY created_at DESC',
        (f'%{q}%', f'%{q}%')
    )
    posts = [dict(row) for row in cur.fetchall()]
    return jsonify(posts)


@app.route('/stats', methods=['GET'])
def blog_stats():
    db = get_db()
    cur = db.execute('SELECT COUNT(*) as n FROM posts')
    post_count = cur.fetchone()['n']
    cur = db.execute('SELECT COUNT(*) as n FROM comments')
    comment_count = cur.fetchone()['n']
    cur = db.execute(
        'SELECT author, COUNT(*) as n FROM posts GROUP BY author ORDER BY n DESC LIMIT 5'
    )
    top_authors = [dict(r) for r in cur.fetchall()]
    return jsonify({
        'posts': post_count,
        'comments': comment_count,
        'top_authors': top_authors,
    })


@app.route('/posts/<int:post_id>/comments', methods=['GET'])
def list_comments(post_id):
    db = get_db()
    cur = db.execute(
        'SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC',
        (post_id,)
    )
    comments = [dict(r) for r in cur.fetchall()]
    return jsonify(comments)


@app.route('/health', methods=['GET'])
def health_check():
    db = get_db()
    try:
        db.execute('SELECT 1')
        return jsonify({'status': 'ok', 'database': 'connected'})
    except sqlite3.Error:
        return jsonify({'status': 'error', 'database': 'down'}), 503


@app.errorhandler(404)
def not_found(e):
    return jsonify({'error': 'Resource not found'}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    with app.app_context():
        init_db()
    app.run(debug=True, port=5000)
