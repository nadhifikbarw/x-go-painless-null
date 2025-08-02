-- +goose Up
CREATE TABLE individuals (
    id text NOT NULL PRIMARY KEY,
    -- Proxy for org table as example
    org_id text NOT NULL,
    -- Set all info fields nullable to allow partial saving
    uinfin text,
    name text,
    aliasname text,
    hanyupinyin_name text,
    hanyupinyin_aliasname text,
    married_name text,
    dob date,
    nationality text,
    created_at timestamp NOT NULL,
    updated_at timestamp NOT NULL,
    deleted_at timestamp
);

CREATE TABLE individual_addresses (
  id text NOT NULL PRIMARY KEY,
  individual_id text NOT NULL,
  -- Set all info fields nullable to allow partial saving
  address_line_1 text,
  address_line_2 text,
  address_line_3 text,
  postal_code text,
  city text,
  country_code text,
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL,
  deleted_at timestamp
)

-- +goose Down
DROP TABLE IF EXISTS individuals;
DROP TABLE IF EXISTS individual_addresses;
