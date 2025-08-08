# Go Painless Null Binding

In SQL (or JSON), the value `null` typically assigned semantic meaning that indicates whether a piece of data exist, it's also often interpreted as unset/missing value.

Consider a simple data type like a string. It's not an uncommon domain requirement to differentiate the handling between empty string (`""`, Go zero value) and `null`. In fields such as data analysis, understanding the distinction between NULL and empty string considered a crucial part of accurate data processing, analysis, and interpretation.

Due to the lack of `null` in Go, modelling domain struct that interfaces with JSON/SQL can be awkward. Most obvious alternative to address this is by using pointer type to model `null` value.

```go
// Example of SQL Model using pointer type in GORM from https://gorm.io/docs/models.html
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

I personally don't like using pointer type to handle nullability. I've also heard suggestions to change your domain models around the zero value, as one might argue dealing with `null` in other language can be as painful. But I haven't been able to find this suggestion super practical.

I find having to deal with pointer type (safely) is onerous for nullability, and it can get in the way of getting things done. Furthermore in Go, it often demands extra boilerplate code to handle  proper serialization/deserialization for something that should be relatively simple in scope.

Thus for the sake of it, I went to explore properties of:

* `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`
* `sql.NullXxX` types from `database/sql`
* `null.XxX` types from `github.com/guregu/null/v6`

to see whether it's possible to have better experience when handling nullability, worry less about boilerplate code, and ease interfacing with SQL/JSON.

This write up explored nullability with primary focus from `sqlc` codegen workflow perspective, but its findings are generic because `sqlc` generate relatively common boilerplate code and uses popular sql packages that uses `database/sql/driver.Valuer` interface. Various libraries handling data interface typically support/use the `Valuer` interface.

## Example Domain Scenario

Let's imagine you're working on improving KYC data collection to support business operation by integrating with gov service. I'm going to borrow [Singapore Myinfo Data Model](https://docs.developer.singpass.gov.sg/docs/data-catalog-myinfo/catalog/personal) to explore this scenario.

We want to introduce autofill feature to ease form filling experience by leveraging Government-supplied information, but user will need to have the ability to correct/append information that might be missing/incorrect from 3rd party integration. To facilitate this UX we want to support partial form / stepped form saving mechanism to reduce friction when users might be unable to finish it in one go.

In order to build meaningful transactional data capture of `Individual` information it's beneficial to distinguish between null-valued vs zero-valued data coming from the third part integration. Thus, our example domain tables are defined such:

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

## Choosing between the `pgx/v5` and `database/sql`

When using `sqlc`, one can configure which sql package to use that facilitate database connection and tailor your db-related logic.

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

We're going to look into code that `sqlc` generated using `database/sql` and `pgx/v5` to see how nullability and JSON interoperability get handled.

`dbsql_pg`, `dbsql_mysql`, and `pgx_pg` packages inside `pkg/gen/gensql` are generated with `emit_pointers_for_null_types: false` without any `overrides`.

> A custom type can support json serialization/deserialization provided by `encoding/json` by implementing [`json.Marshaler`](https://pkg.go.dev/encoding/json#Marshaler) and [`json.Unmarshaler`](https://pkg.go.dev/encoding/json#Unmarshaler) interface. For brevity I'll refer type that implements both interfaces as `JSONOK`.

### `pgx/v5` code generation

`pgx/v5` generated code doesn't use pointer type for nullability, instead it uses `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`. It handles nullability using `Valid` field. If we see the generated model from `pgx_pg` we can see:

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

If we look into `pgtype.Text` implementation as example, we can see it uses `Valid` field to facilitate nullability:

```go
// From pgtype.Text implementation
func (src Text) MarshalJSON() ([]byte, error) {
	if !src.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(src.String)
}
```

Thus, to use `pgtype.XxX` types to declare null value, simply set `Valid` field as `false`, or just perform empty initialization.
```go
nullTimestamp := pgtype.Timestamp{Valid: false}
// Empty initialization set Valid as false
nullText := pgtype.Text{}
```

As showcased from `pgtype.Text` internal above, `pgtype.XxX` implements `encoding/json` interfaces making it `JSONOK`.

### `database/sql` code generation

`database/sql` generated code also doesn't use pointer type for nullability, instead it uses `sql.NullXxX` types from `database/sql`. It handles nullability via `Valid` field (same as `pgtype.XxX`). If we see the generated model from both `dbsql_pg` or `dbsql_mysql` we can see:

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

If we look into `sql.NullText` implementation as example, we can see it uses `Valid` field to facilitate nullability:

```go
// Value implements the [driver.Valuer] interface.
func (ns NullString) Value() (driver.Value, error) {
	if !ns.Valid {
		return nil, nil
	}
	return ns.String, nil
}
```

Thus, to use `pgtype.XxX` types to declare null value, simply set `Valid` field as `false`, or just perform empty initialization.

```go
nullTimestamp := sql.NullTime{Valid: false}
// Empty initialization set Valid as false
nullText := sql.String{}
```

### `sql.NullXxX` types are not `JSONOK`

In contrast to `pgtype.XxX` types, `sql.NullXxX` types doesn't implement JSON interfaces types, the internals are pretty minimalist.

Therefore, if you need to use `database/sql`, you might sooner or later feel the need to make extended custom types to make it easier to support JSON interfacing as well.

## Taking It Further with `guregu/null`

The need for such boilerplate support code that offer nullability and sane experience for both SQL and JSON interfaces are the premises behind `github.com/guregu/null/v6`.

It provides that boilerplate custom types to conveniently define structs/models that require nullability, similar to `pgtype.XxX` but not platform-specific.

`guregu/null` has 2 packages `null.XxX` or `zero.XxX`. [Documentation](https://github.com/guregu/null)

All `null.XxX` and `zero.XxX` types relies on the same mechanism that `pgtype.XxX` types use, it implements `database/sql.Scanner` and `database/sql/driver.Valuer`. Since `pgx/v5` provides interoperability support with `database/sql` it can the same custom types that satisfy these interfaces.

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

If we look into `null.String` implementation as example, we can see it actually just embeds the `sql.NullString` type to cover nullability, but extend implementation for `encoding/json` interfaces to make each type `JSONOK`:

```go
// from: guregu/null.String

// String is a nullable string. It supports SQL and JSON serialization.
// It will marshal to null if null. Blank string input will be considered null.
type String struct {
	sql.NullString // Just wraps sql.NullString
}

// [...]
// Implements JSON interfaces to make it JSONOK

// MarshalJSON implements json.Marshaler.
// It will encode null if this String is null.
func (s String) MarshalJSON() ([]byte, error) {
	if !s.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(s.String)
}

// [...]
```

## Example Convenient DTO

Let's imagine now you need to implement the endpoint that allow user to correct/amend some information that might still be missing, it's a simple REST endpoint that takes `application/json` payload.

Now, since you have the shared types to represent nullability that work with JSON and SQL interfaces. It's possible to make the json body binding that conveniently map into the SQL mode. Note: I don't mean sharing SQL/storage layer model for endpoint, but using the same `null.String` type for field in model for each layer.

```go
// Imagine you have Web UI stepped form
// allowing user to correct their uinfin and names

type UinfinNamesForm struct {
	uinfin                string
	name                  null.String
	hanyupinyin_name      null.String
	hanyupinyin_aliasname null.String
	married_name          null.String
}
```

### Using `pgtype.XxX` ?

If you have access to it and don't want to add more dependencies. It's technically an option you can use `pgtype.XxX` to handle this concerns too:

```go
type PgUinfinNamesForm struct {
	uinfin                string
	name                  pgtype.Text
	hanyupinyin_name      pgtype.Text
	hanyupinyin_aliasname pgtype.Text
	married_name          pgtype.Text
}
```

But it depends on your taste and sensitivity around separation of concerns, as someone might find this approach "iffy" because you're leaking database details in your json body binding. An example of implementation that someone might find very leaky:

```go
type PgAgeForm struct {
	Age pgtype.Int4 // One might find this is leaky since it leaks data size of your storage layer
}
```

## Overriding `sqlc` generated code to use `guregu/null`

If you want examples of using `guregu/null` as part of `sqlc` workflow to instruct `sqlc` to generate code using these types, you can take a look inside [`sqlc.yaml`](./sqlc.yaml) where I configure `overrides` to use `null.XxX` types for nullable fields.

You can read the generated code in [`guregu_pg`](./pkg/gen/gensql/guregu_pg/) or [`guregu_mysql`](./pkg/gen/gensql/guregu_mysql/) to see how generated code looks like with `pgx/v5` or `database/sql`.

The generated code are actually very simple and humble boilerplate code. A snippet of generated model with partially overridden with `guregu/null` types:

```go
type Individual struct {
	ID                   string             `json:"id"`
	OrgID                string             `json:"org_id"`
	Uinfin               null.String        `json:"uinfin"`
	Name                 null.String        `json:"name"`
	Aliasname            null.String        `json:"aliasname"`
	HanyupinyinName      null.String        `json:"hanyupinyin_name"`
	HanyupinyinAliasname null.String        `json:"hanyupinyin_aliasname"`
	MarriedName          null.String        `json:"married_name"`
	Dob                  null.Time          `json:"dob"`
	Nationality          null.String        `json:"nationality"`
	CreatedAt            pgtype.Timestamptz `json:"created_at"`
	UpdatedAt            pgtype.Timestamptz `json:"updated_at"`
	DeletedAt            null.Time          `json:"deleted_at"`
}
```

You can see how sharing types that support common JSON/SQL interfaace can make it easy and convenient to model and map the necessary data between transport, business, and storage layer that need to facilitate nullability.

## Notes on JSON Binding and Data Validation

Since `JSONOK` types implement `json.Unmarshaler` common binding logic that rely on `json.Unmarshaler` should work accordingly when using `null.XxX` types.

Example, [Echo Web Framework](https://echo.labstack.com/docs/binding#data-sources):
>Echo supports the following tags specifying data sources:
> [...]
> * json - request body. Uses builtin Go json package for UNMARSHALLING.
> * xml - request body. Uses builtin Go xml package for unmarshalling.
> * form - form data. Values are taken from query and request body. Uses Go standard library form parsing.

For validation, you need to check how validation library of choice handles custom types, for example [`go-playground/validator`](https://github.com/go-playground/validator) can support custom type but [asks you to register it beforehand](https://github.com/nadhifikbarw/x-go-validator-valuer/blob/main/main.go).

## Notes on VSCode + Go extension

As I'm writing this write up, I found out that `sqlc generate` sometimes will get prevented to generate code when being called using Intergrated VSCode Terminal if you already have generated files in the target folders.

I suspect `sqlc` attempts to modify code got blocked by VSCode since the generated files contains `DO NOT EDIT`. You will see wraning popup when trying to edit these files manually as well.

As sane prevention, deleting generated files before re-running the `generate` command works.



