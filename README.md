# Go Painless Null Binding

In SQL (or JSON), the value `null` typically has semantic meaning that indicates whether a piece of data exist, this value is typically interpreted as unset/missing instead of its zero value equivalent.

Consider a simple data type like a string. It's not an uncommon domain requirement to clearly differentiate the meaning between empty string (`""`, zero value) and `null`. In fields such as data analysis, understanding the distinction between NULL and empty string considered a crucial part of accurate data processing, analysis, and interpretation.

Thus, In go modelling a high-level domain struct, that needs to interface with JSON/SQL, often feels awkward. As an alternative to address the lack of `null` in Go, pointer types are often used as an alternative.

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

I don't think using pointer to model optional value is that neat. In ideal world one might be suggested to change the domain model itself around the zero value as one might argue dealing with `null` in other language can be as painful. But I haven't found this suggestion that useful.

I find having to deal with pointer safely to facilitate nullability can get in the way of getting things done (and specifically in Go, it demands extra boilerplate code to cover proper serialization/deserialization across interfaces) for something that should be relatively simple in scope.

Thus for the sake of it, I want to explore properties of `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`, `sql.NullXxX` types from `database/sql`, and `github.com/guregu/null/v6` to see whether it's possible to have better experience handling nullability, with less boilerplate code to handle interoperability with JSON.

The write up below observe nullability with help of `sqlc` codegen workflow, but its findings should be generic because `sqlc` generate code that uses popular sql packages that work with the generic `database/sql/driver.Valuer` interface. Various library related to IO interfacing typically support the `Valuer` interface.

## Example Domain Scenario

Let's imagine you're working on improving KYC data collection to support operational process by integrating with gov service. I'm going to use [Singapore Myinfo Data Model](https://docs.developer.singpass.gov.sg/docs/data-catalog-myinfo/catalog/personal) to explore this scenario.

In order to build meaningful data capture of `Individual` information it might be beneficial to avoid conflating null-valued vs empty-valued information. Our example tables defined as:

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

For UX sake, whenever you try to collect lengthy info from users, it's almost always best to have partial form / stepped form saving mechanism in place to reduce friction when users might be unable to finish it in one go.

In this scenario we also imagine introducing autofill feature to make form filling experience even easier by leveraging Government-supplied information, user then will have the ability to correct any information that autofilled in case of mismatch/missing data from the 3rd party integration.

## Choosing between the `pgx/v5` and `database/sql`

When using `sqlc` one can configure  which sql package to use to facilitate database connection and interfacing with your db-related logic.

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

`dbsql_pg`, `dbsql_mysql`, and `pgx_pg` packages inside `pkg/gen/gensql` are generated without any `overrides` with `emit_pointers_for_null_types: false` set.

> A custom type can support json serialization/deserialization provided by `encoding/json` by implementing [`json.Marshaler`](https://pkg.go.dev/encoding/json#Marshaler) and [`json.Unmarshaler`](https://pkg.go.dev/encoding/json#Unmarshaler) interface. For brevity I'll refer type that implements both interfaces as `JSONOK`.

### `pgx/v5` code generation

`pgx/v5` generated code handle nullability without pointer types by using `pgtype.XxX` types from `github.com/jackc/pgx/v5/pgtype`. Each type typically handles nullability via `Valid` field. If we see the generated model from `pgx_pg` we can see:

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

If we look into `pgtype.Text` implementation as example, we can see it uses `Valid` field to mark nullability:

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

As showcased from `pgtype.Text` internal above, most `pgtype.XxX` implements `encoding/json` interfaces making it `JSONOK`.

### `database/sql` code generation

`database/sql` generated code handle nullability without pointer types by using `sql.NullXxX` types from `database/sql`. Each type typically handles nullability via `Valid` field (similar mechanism to `pgtype.XxX`). If we see the generated model from both `dbsql_pg` or `dbsql_mysql` we can see:

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

If we look into `sql.NullText` implementation as example, we can see it uses `Valid` field to mark nullability:

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

In contrast to `pgtype.XxX` types which implement JSON interfaces, `sql.NullXxX` types internal are pretty minimalist.

Therefore, if you need to use `database/sql`, you might eventually feel the needs for better mechanisms that offer interoperability between your database model and logic for that ask for JSON interfaces.

If you want to support JSON interfaces for `sql.NullXxX` types, having boilerplate support code via simple DTO, or extending types that to make such types `JSONOK` to handle JSON interface will be the only path forward.

## Taking It Further with `guregu/null`

The need for such boilerplate support code that offer nullability and reasonable SQL+JSON interfacing are the premises behind `github.com/guregu/null/v6`.

It provides that boilerplate pre-made custom types to conveniently define structs/models that require nullability, similar to `pgtype.XxX` but not platform-specific.

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

If we look into `null.String` implementation as example, we can see it actually embeds the `sql.NullString` type to cover nullability, but also implements `encoding/json` interfaces to make each type `JSONOK`:

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

Let's imagine now you need to implement endpoint that allow user to correct or amend some information that might still be missing, it's a simple REST endpoint that takes `application/json` payload.

Now since you have shared types that can represent nullability that work with JSON and SQL interfaces, it's possible to define your DTO struct as such to make it convenient to map these field into the SQL model.

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

So you can consider `guregu/null` if you want these type of convenience, especially when you're not using Postgres database (e.g. you're using sqlite sqlite) or simply want to use `database/sql` instead (since `database/sql` also support postgres).

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

But it depends on your taste and sensitivity around separation of concerns, as someone might find this approach "iffy" because you're leaking database details in your DTO. An example of implementation that someone might find very leaky:

```go
type PgAgeForm struct {
	Age pgtype.Int4
}
```

## Overriding `sqlc` generated code to use `guregu/null`

If you want examples of using `guregu/null` as part of `sqlc` workflow to instruct `sqlc` to generate code using these types, you can take a look inside [`sqlc.yaml`](./sqlc.yaml) where I configure `overrides` to use custom types on fields that need nullability.

You can also read the generated code in [`guregu_pg`](./pkg/gen/gensql/guregu_pg/) or [`guregu_mysql`](./pkg/gen/gensql/guregu_mysql/) to see how generated code looks like with `pgx/v5` or `database/sql`. It's actually simple and humble code.

Here is  a snippet of generated model with `guregu/null` overrides:

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

You can see how sharing types accross DTO and SQL can make it convenient for writing your business logic.

## Notes on Binding and Validation

Since `JSONOK` types implement `json.Unmarshaler` common binding logic that rely on `json.Unmarshaler` should work accordingly when using these custom types.

Example, [Echo Web Framework](https://echo.labstack.com/docs/binding#data-sources):
>Echo supports the following tags specifying data sources:
>
> * query - query parameter
> * param - path parameter (also called route)
> * header - header parameter
> * json - request body. Uses builtin Go json package for UNMARSHALLING.
> * xml - request body. Uses builtin Go xml package for unmarshalling.
> * form - form data. Values are taken from query and request body. Uses Go standard library form parsing.

For validation, you need to check how validation library of your choice handles custom types, for example [`go-playground/validator`](https://github.com/go-playground/validator) can support custom type but [asks you to register it beforehand](https://github.com/go-playground/validator/blob/master/_examples/custom/main.go).

## Notes on VSCode + Go extension

As I'm writing this write up, I found out that `sqlc generate` sometimes will get prevented to generate code when being called using the integrated VSCode terminal if you already have generated files in target folders

I suspect `sqlc` attempted to simply modify fields and VSCode prevents code changes on files containing `DO NOT EDIT` as you will see Warning will popup when trying to edit these files manually as well.

As sane prevention deleting generated files before rerunning the `generate` command works for now.



