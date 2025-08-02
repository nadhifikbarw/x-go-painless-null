# Go Painless Null Binding

## Background

In SQL (or JSON), the value `null` typically has semantic meaning that indicate that such data does not exist and should only be interpreted as unset/missing.

Considering simple data type like string. It's not an uncommon domain requirement to clearly differentiate the meaning between empty string (`""`, zero of string in Go) and `null`. In field such as data analyst, understanding the distinction between NULL and empty string considered as crucial part of accurate data processing, analysis, and interpretation.

Thus, modelling a high-level domain struct in Go that need to interface with JSON/SQL often feels awkward. As alternative to facilitate lack of `null` in Go, pointer type is often used as alternative.

```go
// Example of SQL Model using pointer type in gorm from https://gorm.io/docs/models.html
type User struct {
  ID           uint           // Standard field for the primary key
  Name         string         // A regular string field
  Email        *string        // A pointer to a string, allowing for null values
  Age          uint8          // An unsigned 8-bit integer
  Birthday     *time.Time     // A pointer to time.Time, can be null
  MemberNumber sql.NullString // Uses sql.NullString to handle nullable strings
  ActivatedAt  sql.NullTime   // Uses sql.NullTime for nullable time fields
  CreatedAt    time.Time      // Automatically managed by GORM for creation time
  UpdatedAt    time.Time      // Automatically managed by GORM for update time
  ignored      string         // fields that aren't exported are ignored
}
```

IMO, I don't think using pointer to model optional value is that neat. In ideal world one might suggest to change the domain model itself around the zero value as one might argue dealing with `null` in other language can be as painful. But I haven't found this suggestion that useful.

I find having to deal with pointer safely to facilitate nullability value can get in the way of getting things done (and in Go specifically it demands extra boilerplate code to cover serialization/deserialization) for something that should be relatively simple in scope.

Thus for the sake of it, I want to explore `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`, `sql.NullXxX` types from `database/sql`, and `github.com/guregu/null/v6` to see how to have better experience handling nullability, with less boilerplate code when handling interopability with JSON.

I'm going to explore how to use these types to configure `sqlc` codegen workflow.

## Scenario

Let's imagine you're working on improving KYC data collection to support operational process by integrating with gov service. I'm going to use [Singapore Myinfo Data Model](https://docs.developer.singpass.gov.sg/docs/data-catalog-myinfo/catalog/personal) to explore this scenario.

In order to build meaningful data capture of `Individual` information it might be beneficial to avoid conflating null-valued vs empty-valued information. Thus our example tables will be defined as:

```sql
-- +goose Up
CREATE TABLE individuals (
    id text NOT NULL PRIMARY KEY,
    -- Proxy for org table as example
    org_id text NOT NULL
    -- Set all info fields nullable to allow partial saving
    uinfin text,
    "name" text,
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
  deleted_at timestamp NOT NULL,
)
-- the rest...
```

For UX sake, whenever you want to collect lengthy info from users, it's almost always best to have partial form / stepped form save mechanism in place to reduce friction when users might be unable to finish it in one go. In this scenario we want to introduce autofill feature to make form filling experience even easier by leveraging Government-supplied information.

## Choosing between the `pgx/v5` and `database/sql`

When you're using `sqlc` you have the option to specify which sql package you want to use to manage your database connection and interface your db-related logic.

> From: https://github.com/jackc/pgx?tab=readme-ov-file#choosing-between-the-pgx-and-databasesql-interfaces
>
> The pgx interface is faster. Many PostgreSQL specific features such as LISTEN / NOTIFY and COPY are not available through the database/sql interface.
>
> The pgx interface is recommended when:
>
> 1. The application only targets PostgreSQL.
> 2. No other libraries that require database/sql are in use.
>
> It is also possible to use the database/sql interface and convert a connection to the lower-level pgx interface as needed.

We're going to look into code that `sqlc` generated when using `database/sql` and `pgx/v5` to see which one can offer better interopability to handle `null` value.

Let's observe `dbsql_pg`, `dbsql_mysql`, and `pgx_pg` packages inside `pkg/gen/gensql` that are generated without `overrides` and `emit_pointers_for_null_types: false`

> To support json serialization/deserialization provided by `encoding/json` stdlib a custom type can implement [`json.Marshaler`](https://pkg.go.dev/encoding/json#Marshaler) and [`json.Unmarshaler`](https://pkg.go.dev/encoding/json#Unmarshaler) interface. For brevity i'll refer type that implements both interfaces as `JSONOK`

### `pgx/v5` code generation

When using `pgx/v5` for generation, nullability is supported without using pointer type using `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`. Each type typically handles nullability via `Valid` field. If we observe generated model from `pgx_pg` we can see:

```go
type Individual struct {
	ID                   string             `json:"id"`
	OrgID                string             `json:"org_id"`
	Uinfin               pgtype.Text        `json:"uinfin"`
	Name                 pgtype.Text        `json:"name"`
	Aliasname            pgtype.Text        `json:"aliasname"`
	HanyupinyinName      pgtype.Text        `json:"hanyupinyin_name"`
	HanyupinyinAliasname pgtype.Text        `json:"hanyupinyin_aliasname"`
	MarriedName          pgtype.Text        `json:"married_name"`
	Dob                  pgtype.Date        `json:"dob"`
	Nationality          pgtype.Text        `json:"nationality"`
	CreatedAt            pgtype.Timestamptz `json:"created_at"`
	UpdatedAt            pgtype.Timestamptz `json:"updated_at"`
	DeletedAt            pgtype.Timestamptz `json:"deleted_at"`
}
```

If we look at `pgtype.Text` as example, we can see it uses `Valid` field to represent nullability:
```go
// From pgtype.Text implementation
func (src Text) MarshalJSON() ([]byte, error) {
	if !src.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(src.String)
}
```
Thus, when using `pgtype.XxX` types to declare null value you just need to set `Valid` field as false, or simply empty initialization
```go
nullTimestamp := pgtype.Timestamp{Valid: false}
nullText := pgtype.Text{} // Empty initialization set Valid as false
```

As showcased above, most `pgtype.XxX` implements `MarshalJSON` thus making it `JSONOK`.

### `database/sql` code generation

When using `database/sql` for generation, nullability is supported without using pointer type using `sql.NullXxX` types from `database/sql`. Similar with `pgtype.XxX` mechanism. Each type typically handle nullability via `Valid` field. If we observe generated model from `dbsq_*` packages, we can see:

```go
type Individual struct {
	ID                   string         `json:"id"`
	OrgID                string         `json:"org_id"`
	Uinfin               sql.NullString `json:"uinfin"`
	Name                 sql.NullString `json:"name"`
	Aliasname            sql.NullString `json:"aliasname"`
	HanyupinyinName      sql.NullString `json:"hanyupinyin_name"`
	HanyupinyinAliasname sql.NullString `json:"hanyupinyin_aliasname"`
	MarriedName          sql.NullString `json:"married_name"`
	Dob                  sql.NullTime   `json:"dob"`
	Nationality          sql.NullString `json:"nationality"`
	CreatedAt            time.Time      `json:"created_at"`
	UpdatedAt            time.Time      `json:"updated_at"`
	DeletedAt            sql.NullTime   `json:"deleted_at"`
}
```

  If we look at `sql.NullString` as example, we can see it uses `Valid` field to represent nullability:

```go
// Value implements the [driver.Valuer] interface.
func (ns NullString) Value() (driver.Value, error) {
	if !ns.Valid {
		return nil, nil
	}
	return ns.String, nil
}
```
Thus, when using `sql.NullXxX` types to declare null value you just need to set `Valid` field as false, or simply empty initialization

```go
nullTimestamp := sql.NullTime{Valid: false}
nullText := sql.String{} // Empty initialization set Valid as false
```

## `sql.NullXxX` types are not `JSONOK`

In contrast to `pgtype.XxX` that implements JSON interfaces, `sql.NullXxX` types are pretty minimalist. Therefore, if you have a valid needs that require you to use `database/sql` and eventually find the need for better interopability between your database model and JSON interface, you will find yourself needing to  write boilerplate further either via DTO, or your extended types to make it `JSONOK`.

## Taking It Further with `guregu/null`

The need for boilerplate structs to handle nullability and SQL+JSON interfacing is the premise behind `github.com/guregu/null/v6`. You can use premade boilerplate structs to conveniently define models using types that handle nullability and SQL, JSON interfacing.

For `sqlc` since we either  use `database/sql` or `pgx/v5` for SQL interfacing. Let's see what each sql package interfaces for custom types. Since `pgx/v5` supports `database/sql.Scanner` and `database/sql/driver.Valuer` interfaces, any custom type that want to work with both packages need to implement those interfaces.

```go
// from: database/sql
type Scanner interface {
	Scan(src any) error
}

// from: database/sql/driver
type Value any
type Valuer interface {
	// Value returns a driver Value.
	// Value must not panic.
	Value() (Value, error)
}
```

All `null.XxX` and `zero.XxX` types implement `database/sql.Scanner` and `database/sql/driver.Valuer`.

```go
// from: guregu/null

// String is a nullable string. It supports SQL and JSON serialization.
// It will marshal to null if null. Blank string input will be considered null.
type String struct {
	sql.NullString // Just wraps sql.NullString
}

// But also makes it JSONOK

// MarshalJSON implements json.Marshaler.
// It will encode null if this String is null.
func (s String) MarshalJSON() ([]byte, error) {
	if !s.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(s.String)
}
```

If you want better experience of handling nullability and making SQL/JSON interfacing plays well, e.g. to write HTTP request/response DTO to facilitate json binding but handle SQL model conversion smoothly. You can consider `guregu/null` if you can't use `pgtype.XxX` because you're not using Postgres database (e.g. for sqlite).

If you have access to `pgtype.XxX` and don't want to add more dependencies. I think `pgtype.XxX` can handle this concern too. but might be "iffy" because you're leaking your database details (`pg...`) in your DTO.

## Note on VSCode + Go extension

Sometimes, `sqlc generate` will get blocked for making changes when being run using integrated VScode terminal. I suspect it's because VSCode can prevent code changes in flies that contains `DO NOT EDIT` as you will see warning when trying to edit these files manually . As prevention deleting generated files before rerunning generate command works for now.



