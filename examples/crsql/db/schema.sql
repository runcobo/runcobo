CREATE TABLE authors (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  bio text
);

COMMENT ON TABLE authors IS 'Authors table';
COMMENT ON COLUMN authors.name IS 'Author name';
COMMENT ON COLUMN authors.bio IS 'Author biography';

CREATE TABLE books (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  author_id bigint NOT NULL REFERENCES authors(id),
  title text NOT NULL,
  isbn text NOT NULL UNIQUE
);

COMMENT ON TABLE books IS 'Books table';
COMMENT ON COLUMN books.author_id IS 'Author identifier';
COMMENT ON COLUMN books.title IS 'Book title';
COMMENT ON COLUMN books.isbn IS 'Book number';
