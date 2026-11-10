package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestRoutes(t *testing.T) {
	server := httptest.NewServer(handler())
	defer server.Close()
	for _, c := range []struct {
		path   string
		status int
		body   string
	}{
		{"/healthz", 200, "ok\n"},
		{"/", 200, "hello from a minimal image\n"},
		{"/missing", 404, ""},
	} {
		response, err := http.Get(server.URL + c.path)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if response.StatusCode != c.status || (c.body != "" && string(body) != c.body) {
			t.Errorf("%s: got %d %q, want %d %q", c.path, response.StatusCode, body, c.status, c.body)
		}
	}
}
