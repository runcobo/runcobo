-- name: CreateAuthor :one
INSERT INTO authors (name, bio)
VALUES (sqlc.arg(name), sqlc.narg(bio))
RETURNING id, name, bio;

-- name: GetAuthor :one
SELECT id, name, bio FROM authors WHERE id = sqlc.arg(id);

-- name: ListAuthors :many
SELECT id, name, bio FROM authors ORDER BY id;

-- name: UpdateAuthor :one
UPDATE authors SET
  name = CASE WHEN sqlc.arg(name_present)::boolean THEN sqlc.narg(name)::text ELSE name END,
  bio = CASE WHEN sqlc.arg(bio_present)::boolean THEN sqlc.narg(bio)::text ELSE bio END
WHERE id = sqlc.arg(id)
RETURNING id, name, bio;

-- name: CreateBook :one
INSERT INTO books (author_id, title, isbn)
VALUES (sqlc.arg(author_id), sqlc.arg(title), sqlc.arg(isbn))
RETURNING id, author_id, title, isbn;

-- name: GetBookByIsbn :one
SELECT id, author_id, title, isbn FROM books WHERE isbn = sqlc.arg(isbn);
