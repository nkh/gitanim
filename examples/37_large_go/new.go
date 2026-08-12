// Package main implements a URL shortener HTTP API with cleanly separated
// handlers, middleware, structured logging, and request-scoped context
// propagation.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type ShortURL struct {
	ID        int64      `json:"id"`
	Slug      string     `json:"slug"`
	Target    string     `json:"target"`
	CreatedAt time.Time  `json:"created_at"`
	ExpiresAt *time.Time `json:"expires_at,omitempty"`
	Visits    int64      `json:"visits"`
	CreatedBy string     `json:"created_by,omitempty"`
}

type Stats struct {
	TotalURLs   int64       `json:"total_urls"`
	TotalVisits int64       `json:"total_visits"`
	TopURLs     []URLVisits `json:"top_urls"`
	GeneratedAt time.Time   `json:"generated_at"`
}

type URLVisits struct {
	Slug   string `json:"slug"`
	Visits int64  `json:"visits"`
}

type CreateRequest struct {
	Slug            string `json:"slug"`
	Target          string `json:"target"`
	ExpiresInSeconds int   `json:"expires_in_seconds"`
	CreatedBy       string `json:"created_by"`
}

type UpdateRequest struct {
	Target          string `json:"target"`
	ExpiresInSeconds int   `json:"expires_in_seconds"`
}

type APIError struct {
	Code    int    `json:"-"`
	Message string `json:"error"`
	Detail  string `json:"detail,omitempty"`
}

func (e *APIError) Error() string { return e.Message }

func NewAPIError(code int, msg string) *APIError {
	return &APIError{Code: code, Message: msg}
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

type Store interface {
	List(ctx context.Context, limit, offset int) ([]ShortURL, error)
	Get(ctx context.Context, slug string) (*ShortURL, error)
	Create(ctx context.Context, slug, target, createdBy string, expiresIn int) (*ShortURL, error)
	Update(ctx context.Context, slug, target string, expiresIn int) error
	Delete(ctx context.Context, slug string) error
	IncrementVisit(ctx context.Context, slug string) error
	Stats(ctx context.Context) (*Stats, error)
}

type pgStore struct {
	db *sql.DB
}

func NewPgStore(db *sql.DB) Store {
	return &pgStore{db: db}
}

func (s *pgStore) List(ctx context.Context, limit, offset int) ([]ShortURL, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, slug, target, created_at, expires_at, visits, created_by
		 FROM urls ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
		limit, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("list urls: %w", err)
	}
	defer rows.Close()
	urls := make([]ShortURL, 0, limit)
	for rows.Next() {
		u, err := scanURL(rows)
		if err != nil {
			return nil, err
		}
		urls = append(urls, *u)
	}
	return urls, rows.Err()
}

func (s *pgStore) Get(ctx context.Context, slug string) (*ShortURL, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, slug, target, created_at, expires_at, visits, created_by
		 FROM urls WHERE slug = $1`, slug,
	)
	return scanURL(row)
}

func (s *pgStore) Create(ctx context.Context, slug, target, createdBy string, expiresIn int) (*ShortURL, error) {
	var expiresAt sql.NullTime
	if expiresIn > 0 {
		expiresAt = sql.NullTime{
			Time:  time.Now().Add(time.Duration(expiresIn) * time.Second),
			Valid: true,
		}
	}
	row := s.db.QueryRowContext(ctx,
		`INSERT INTO urls (slug, target, expires_at, created_by)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, slug, target, created_at, expires_at, visits, created_by`,
		slug, target, expiresAt, createdBy,
	)
	return scanURL(row)
}

func (s *pgStore) Update(ctx context.Context, slug, target string, expiresIn int) error {
	var expiresAt sql.NullTime
	if expiresIn > 0 {
		expiresAt = sql.NullTime{
			Time:  time.Now().Add(time.Duration(expiresIn) * time.Second),
			Valid: true,
		}
	}
	if target == "" {
		_, err := s.db.ExecContext(ctx,
			`UPDATE urls SET expires_at = $1 WHERE slug = $2`,
			expiresAt, slug,
		)
		return err
	}
	_, err := s.db.ExecContext(ctx,
		`UPDATE urls SET target = $1, expires_at = $2 WHERE slug = $3`,
		target, expiresAt, slug,
	)
	return err
}

func (s *pgStore) Delete(ctx context.Context, slug string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM urls WHERE slug = $1`, slug)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *pgStore) IncrementVisit(ctx context.Context, slug string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE urls SET visits = visits + 1 WHERE slug = $1`, slug)
	return err
}

func (s *pgStore) Stats(ctx context.Context) (*Stats, error) {
	var total, totalVisits int64
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*), COALESCE(SUM(visits), 0) FROM urls`,
	).Scan(&total, &totalVisits)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT slug, visits FROM urls ORDER BY visits DESC LIMIT 5`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	top := make([]URLVisits, 0, 5)
	for rows.Next() {
		var v URLVisits
		if err := rows.Scan(&v.Slug, &v.Visits); err != nil {
			return nil, err
		}
		top = append(top, v)
	}
	return &Stats{
		TotalURLs:   total,
		TotalVisits: totalVisits,
		TopURLs:     top,
		GeneratedAt: time.Now().UTC(),
	}, rows.Err()
}

type scanner interface {
	Scan(dest ...any) error
}

func scanURL(s scanner) (*ShortURL, error) {
	var u ShortURL
	var expiresAt sql.NullTime
	var createdBy sql.NullString
	if err := s.Scan(&u.ID, &u.Slug, &u.Target, &u.CreatedAt,
		&expiresAt, &u.Visits, &createdBy); err != nil {
		return nil, err
	}
	if expiresAt.Valid {
		u.ExpiresAt = &expiresAt.Time
	}
	if createdBy.Valid {
		u.CreatedBy = createdBy.String
	}
	return &u, nil
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

type Server struct {
	store  Store
	logger *slog.Logger
	mux    *http.ServeMux
}

func NewServer(store Store, logger *slog.Logger) *Server {
	s := &Server{store: store, logger: logger, mux: http.NewServeMux()}
	s.routes()
	return s
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /api/urls", s.handleList)
	s.mux.HandleFunc("POST /api/urls", s.handleCreate)
	s.mux.HandleFunc("GET /api/urls/{slug}", s.handleGet)
	s.mux.HandleFunc("DELETE /api/urls/{slug}", s.handleDelete)
	s.mux.HandleFunc("PATCH /api/urls/{slug}", s.handleUpdate)
	s.mux.HandleFunc("GET /api/stats", s.handleStats)
	s.mux.HandleFunc("GET /r/{slug}", s.handleRedirect)
	s.mux.HandleFunc("GET /healthz", s.handleHealthz)
}

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

func (s *Server) LoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		s.logger.Info("http request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"bytes", rec.bytes,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", r.RemoteAddr,
		)
	})
}

func (s *Server) RecoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				s.logger.Error("panic recovered",
					"error", rec,
					"path", r.URL.Path,
				)
				writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *Server) CORSMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

func (s *Server) handleList(w http.ResponseWriter, r *http.Request) {
	limit, offset := parsePagination(r, 50, 0)
	urls, err := s.store.List(r.Context(), limit, offset)
	if err != nil {
		s.logger.Error("list urls failed", "error", err)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"urls":   urls,
		"limit":  limit,
		"offset": offset,
	})
}

func (s *Server) handleCreate(w http.ResponseWriter, r *http.Request) {
	var body CreateRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, NewAPIError(http.StatusBadRequest, "invalid body"))
		return
	}
	if body.Target == "" {
		writeError(w, NewAPIError(http.StatusBadRequest, "target required"))
		return
	}
	if body.Slug == "" {
		body.Slug = generateSlug()
	}
	u, err := s.store.Create(r.Context(), body.Slug, body.Target, body.CreatedBy, body.ExpiresInSeconds)
	if err != nil {
		if strings.Contains(err.Error(), "unique") {
			writeError(w, NewAPIError(http.StatusConflict, "slug in use"))
			return
		}
		s.logger.Error("create url failed", "error", err)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusCreated, u)
}

func (s *Server) handleGet(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if slug == "" {
		writeError(w, NewAPIError(http.StatusBadRequest, "slug required"))
		return
	}
	u, err := s.store.Get(r.Context(), slug)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, NewAPIError(http.StatusNotFound, "not found"))
		return
	}
	if err != nil {
		s.logger.Error("get url failed", "error", err, "slug", slug)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleDelete(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	if err := s.store.Delete(r.Context(), slug); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, NewAPIError(http.StatusNotFound, "not found"))
			return
		}
		s.logger.Error("delete url failed", "error", err, "slug", slug)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) handleUpdate(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	var body UpdateRequest
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, NewAPIError(http.StatusBadRequest, "invalid body"))
		return
	}
	if err := s.store.Update(r.Context(), slug, body.Target, body.ExpiresInSeconds); err != nil {
		s.logger.Error("update url failed", "error", err, "slug", slug)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	stats, err := s.store.Stats(r.Context())
	if err != nil {
		s.logger.Error("stats failed", "error", err)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

func (s *Server) handleRedirect(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	u, err := s.store.Get(r.Context(), slug)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, NewAPIError(http.StatusNotFound, "not found"))
		return
	}
	if err != nil {
		s.logger.Error("redirect lookup failed", "error", err, "slug", slug)
		writeError(w, NewAPIError(http.StatusInternalServerError, "internal error"))
		return
	}
	if u.ExpiresAt != nil && time.Now().After(*u.ExpiresAt) {
		writeError(w, NewAPIError(http.StatusGone, "expired"))
		return
	}
	// Increment visit count asynchronously with a short-lived context.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := s.store.IncrementVisit(ctx, slug); err != nil {
			s.logger.Warn("increment visit failed", "slug", slug, "error", err)
		}
	}()
	http.Redirect(w, r, u.Target, http.StatusFound)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 1*time.Second)
	defer cancel()
	if pinger, ok := s.store.(interface{ Ping(context.Context) error }); ok {
		if err := pinger.Ping(ctx); err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{
				"status":   "down",
				"database": "unreachable",
			})
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":   "ok",
		"database": "connected",
	})
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("encode json failed", "error", err)
	}
}

func writeError(w http.ResponseWriter, err *APIError) {
	writeJSON(w, err.Code, err)
}

func decodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func parsePagination(r *http.Request, defaultLimit, defaultOffset int) (int, int) {
	limit := defaultLimit
	offset := defaultOffset
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}
	return limit, offset
}

func generateSlug() string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, 6)
	now := time.Now().UnixNano()
	for i := range b {
		b[i] = charset[(now>>(uint(i)*7))%int64(len(charset))]
	}
	return string(b)
}

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

func initSchema(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS urls (
			id BIGSERIAL PRIMARY KEY,
			slug TEXT UNIQUE NOT NULL,
			target TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
			expires_at TIMESTAMPTZ,
			visits BIGINT NOT NULL DEFAULT 0,
			created_by TEXT
		);
		CREATE INDEX IF NOT EXISTS urls_slug_idx ON urls (slug);
	`)
	return err
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://localhost/shortener?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		logger.Error("db open failed", "error", err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		logger.Error("db ping failed", "error", err)
		os.Exit(1)
	}
	if err := initSchema(ctx, db); err != nil {
		logger.Error("schema init failed", "error", err)
		os.Exit(1)
	}
	store := NewPgStore(db)
	server := NewServer(store, logger)
	wrapped := server.LoggingMiddleware(
		server.RecoverMiddleware(
			server.CORSMiddleware(server),
		),
	)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	logger.Info("listening", "port", port)
	httpSrv := &http.Server{
		Addr:              ":" + port,
		Handler:           wrapped,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}
	if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("listen failed", "error", err)
		os.Exit(1)
	}
}
