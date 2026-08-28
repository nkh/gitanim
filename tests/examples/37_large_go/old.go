// Package main implements a URL shortener HTTP API in a single file with
// inline logic. Routes are dispatched via a single ServeHTTP method that
// inspects the path and method.
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
)

type ShortURL struct {
	ID        int64     `json:"id"`
	Slug      string    `json:"slug"`
	Target    string    `json:"target"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	Visits    int64     `json:"visits"`
	CreatedBy string    `json:"created_by"`
}

type API struct {
	db     *sql.DB
	mu     sync.RWMutex
	cache  map[string]*ShortURL
	logger *log.Logger
}

var api *API

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://localhost/shortener?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("db open: %v", err)
	}
	if err := db.Ping(); err != nil {
		log.Fatalf("db ping: %v", err)
	}
	api = &API{
		db:     db,
		cache:  make(map[string]*ShortURL),
		logger: log.New(os.Stdout, "[shortener] ", log.LstdFlags),
	}

	if err := initSchema(db); err != nil {
		log.Fatalf("schema: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	api.logger.Printf("listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, http.HandlerFunc(handler)))
}

func initSchema(db *sql.DB) error {
	_, err := db.Exec(`
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

func handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	path := r.URL.Path
	method := r.Method

	switch {
	case path == "/api/urls" && method == "GET":
		listURLs(w, r)
	case path == "/api/urls" && method == "POST":
		createURL(w, r)
	case path == "/api/urls/" && method == "GET":
		http.Error(w, `{"error":"slug required"}`, http.StatusBadRequest)
		return
	case strings.HasPrefix(path, "/api/urls/") && method == "GET":
		slug := strings.TrimPrefix(path, "/api/urls/")
		getURL(w, r, slug)
	case strings.HasPrefix(path, "/api/urls/") && method == "DELETE":
		slug := strings.TrimPrefix(path, "/api/urls/")
		deleteURL(w, r, slug)
	case strings.HasPrefix(path, "/api/urls/") && method == "PATCH":
		slug := strings.TrimPrefix(path, "/api/urls/")
		updateURL(w, r, slug)
	case path == "/api/stats" && method == "GET":
		statsHandler(w, r)
	case path == "/r/" && method == "GET":
		http.Error(w, `{"error":"slug required"}`, http.StatusBadRequest)
		return
	case strings.HasPrefix(path, "/r/") && method == "GET":
		slug := strings.TrimPrefix(path, "/r/")
		redirect(w, r, slug)
	case path == "/healthz" && method == "GET":
		healthz(w, r)
	default:
		http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
	}
}

func listURLs(w http.ResponseWriter, r *http.Request) {
	limit := 50
	offset := 0
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
	rows, err := api.db.Query(
		`SELECT id, slug, target, created_at, expires_at, visits, created_by
		 FROM urls ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
		limit, offset,
	)
	if err != nil {
		api.logger.Printf("listURLs query: %v", err)
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	urls := []ShortURL{}
	for rows.Next() {
		var u ShortURL
		var expiresAt sql.NullTime
		var createdBy sql.NullString
		if err := rows.Scan(&u.ID, &u.Slug, &u.Target, &u.CreatedAt,
			&expiresAt, &u.Visits, &createdBy); err != nil {
			api.logger.Printf("listURLs scan: %v", err)
			continue
		}
		if expiresAt.Valid {
			u.ExpiresAt = expiresAt.Time
		}
		if createdBy.Valid {
			u.CreatedBy = createdBy.String
		}
		urls = append(urls, u)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"urls":   urls,
		"limit":  limit,
		"offset": offset,
	})
}

func createURL(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Slug      string `json:"slug"`
		Target    string `json:"target"`
		ExpiresIn int    `json:"expires_in_seconds"`
		CreatedBy string `json:"created_by"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}
	if body.Target == "" {
		http.Error(w, `{"error":"target required"}`, http.StatusBadRequest)
		return
	}
	if body.Slug == "" {
		body.Slug = generateSlug()
	}
	var expiresAt sql.NullTime
	if body.ExpiresIn > 0 {
		expiresAt = sql.NullTime{
			Time:  time.Now().Add(time.Duration(body.ExpiresIn) * time.Second),
			Valid: true,
		}
	}
	var u ShortURL
	err := api.db.QueryRow(
		`INSERT INTO urls (slug, target, expires_at, created_by)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, slug, target, created_at, expires_at, visits, created_by`,
		body.Slug, body.Target, expiresAt, body.CreatedBy,
	).Scan(&u.ID, &u.Slug, &u.Target, &u.CreatedAt, &expiresAt, &u.Visits, &u.CreatedBy)
	if err != nil {
		if strings.Contains(err.Error(), "unique") {
			http.Error(w, `{"error":"slug in use"}`, http.StatusConflict)
			return
		}
		api.logger.Printf("createURL insert: %v", err)
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	if expiresAt.Valid {
		u.ExpiresAt = expiresAt.Time
	}
	api.mu.Lock()
	api.cache[u.Slug] = &u
	api.mu.Unlock()
	writeJSON(w, http.StatusCreated, u)
}

func getURL(w http.ResponseWriter, r *http.Request, slug string) {
	api.mu.RLock()
	cached, ok := api.cache[slug]
	api.mu.RUnlock()
	if ok {
		writeJSON(w, http.StatusOK, cached)
		return
	}
	var u ShortURL
	var expiresAt sql.NullTime
	var createdBy sql.NullString
	err := api.db.QueryRow(
		`SELECT id, slug, target, created_at, expires_at, visits, created_by
		 FROM urls WHERE slug = $1`, slug,
	).Scan(&u.ID, &u.Slug, &u.Target, &u.CreatedAt, &expiresAt, &u.Visits, &createdBy)
	if err == sql.ErrNoRows {
		http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
		return
	}
	if err != nil {
		api.logger.Printf("getURL query: %v", err)
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	if expiresAt.Valid {
		u.ExpiresAt = expiresAt.Time
	}
	if createdBy.Valid {
		u.CreatedBy = createdBy.String
	}
	api.mu.Lock()
	api.cache[slug] = &u
	api.mu.Unlock()
	writeJSON(w, http.StatusOK, u)
}

func deleteURL(w http.ResponseWriter, r *http.Request, slug string) {
	_, err := api.db.Exec(`DELETE FROM urls WHERE slug = $1`, slug)
	if err != nil {
		api.logger.Printf("deleteURL: %v", err)
		http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
		return
	}
	api.mu.Lock()
	delete(api.cache, slug)
	api.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func updateURL(w http.ResponseWriter, r *http.Request, slug string) {
	var body struct {
		Target    string `json:"target"`
		ExpiresIn int    `json:"expires_in_seconds"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, `{"error":"invalid body"}`, http.StatusBadRequest)
		return
	}
	var expiresAt sql.NullTime
	if body.ExpiresIn > 0 {
		expiresAt = sql.NullTime{
			Time:  time.Now().Add(time.Duration(body.ExpiresIn) * time.Second),
			Valid: true,
		}
	}
	if body.Target != "" {
		_, err := api.db.Exec(
			`UPDATE urls SET target = $1, expires_at = $2 WHERE slug = $3`,
			body.Target, expiresAt, slug,
		)
		if err != nil {
			api.logger.Printf("updateURL: %v", err)
			http.Error(w, `{"error":"internal"}`, http.StatusInternalServerError)
			return
		}
	}
	api.mu.Lock()
	delete(api.cache, slug)
	api.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func redirect(w http.ResponseWriter, r *http.Request, slug string) {
	var target string
	var expiresAt sql.NullTime
	err := api.db.QueryRow(
		`SELECT target, expires_at FROM urls WHERE slug = $1`, slug,
	).Scan(&target, &expiresAt)
	if err == sql.ErrNoRows {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		api.logger.Printf("redirect query: %v", err)
		http.Error(w, "internal", http.StatusInternalServerError)
		return
	}
	if expiresAt.Valid && time.Now().After(expiresAt.Time) {
		http.Error(w, "expired", http.StatusGone)
		return
	}
	go func() {
		_, _ = api.db.Exec(`UPDATE urls SET visits = visits + 1 WHERE slug = $1`, slug)
	}()
	http.Redirect(w, r, target, http.StatusFound)
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	var total, totalVisits int64
	var top5 []struct {
		Slug   string `json:"slug"`
		Visits int64  `json:"visits"`
	}
	api.db.QueryRow(`SELECT COUNT(*), COALESCE(SUM(visits), 0) FROM urls`).Scan(&total, &totalVisits)
	rows, err := api.db.Query(
		`SELECT slug, visits FROM urls ORDER BY visits DESC LIMIT 5`,
	)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var item struct {
				Slug   string `json:"slug"`
				Visits int64  `json:"visits"`
			}
			rows.Scan(&item.Slug, &item.Visits)
			top5 = append(top5, item)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"total_urls":    total,
		"total_visits":  totalVisits,
		"top_urls":      top5,
		"generated_at":  time.Now().UTC(),
	})
}

func healthz(w http.ResponseWriter, r *http.Request) {
	if err := api.db.Ping(); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status":   "down",
			"database": "unreachable",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":   "ok",
		"database": "connected",
	})
}

func generateSlug() string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, 6)
	for i := range b {
		b[i] = charset[time.Now().UnixNano()%int64(len(charset))]
		time.Sleep(time.Nanosecond)
	}
	return string(b)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		api.logger.Printf("write json: %v", err)
	}
}

func unused() {
	_ = fmt.Sprintf
}
