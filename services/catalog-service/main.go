package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync/atomic"
	"time"
)

type Product struct {
	ID       string  `json:"id"`
	Name     string  `json:"name"`
	Category string  `json:"category"`
	Price    float64 `json:"price"`
	Stock    int     `json:"stock"`
}

var requestCount uint64

var catalog = []Product{
	{ID: "FIN-01", Name: "CloudPulse Zero-Trust Hardware Key", Category: "Security Hardware", Price: 149.99, Stock: 420},
	{ID: "FIN-02", Name: "Enterprise High-Frequency Payment Gateway License", Category: "FinTech SaaS", Price: 999.00, Stock: 85},
	{ID: "FIN-03", Name: "Automated Kubernetes Audit & Compliance Engine", Category: "DevSecOps Tooling", Price: 450.50, Stock: 190},
	{ID: "FIN-04", Name: "Multi-Region Disaster Recovery Vault Add-on", Category: "Cloud Infrastructure", Price: 299.99, Stock: 310},
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"healthy","service":"catalog-service"}`))
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	count := atomic.LoadUint64(&requestCount)
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "# HELP catalog_requests_total Total number of catalog HTTP requests\n")
	fmt.Fprintf(w, "# TYPE catalog_requests_total counter\n")
	fmt.Fprintf(w, "catalog_requests_total %d\n", count)
}

func productsHandler(w http.ResponseWriter, r *http.Request) {
	atomic.AddUint64(&requestCount, 1)
	w.Header().Set("Content-Type", "application/json")
	version := os.Getenv("SERVICE_VERSION")
	if version == "" {
		version = "v1.0.0"
	}
	response := map[string]interface{}{
		"service":   "catalog-service",
		"version":   version,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"products":  catalog,
	}
	json.NewEncoder(w).Encode(response)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/metrics", metricsHandler)
	mux.HandleFunc("/products", productsHandler)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	log.Printf("Catalog Service starting on port %s", port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
