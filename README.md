# Go Painless Null Binding

## Background

In SQL (or JSON), the value `null` typically has semantic meaning that indicate that such data does not exist and should only be interpreted as unset/missing.

Considering simple data type like string. It's not an uncommon domain requirement to clearly differentiate the meaning between empty string (`""`) and `null`. In field such as data analyst understanding the distinction between NULL and empty string considered as crucial part of accurate data processing, analysis, and interpretation.

Thus, modelling a high-level domain struct in Go that need to interface with JSON/SQL often feels awkward. As alternative of lack of `null` in Go, pointer is often used as alternative.

```go
// Example of SQL Model by gorm from https://gorm.io/docs/models.html
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

IMO, I don't think using pointer to model optional value is that neat. In ideal world one might suggest to change the domain model itself around the zero value as one might argue dealing with `null` in other language can be as painful.

I find dealing with pointer safely for optional value can get in the way of getting things done (primarily around serialization/deserialization) for something that should be relatively simple in scope. Thus for the sake of it, I want to explore `https://github.com/guregu/null` library and `sql.NullXxX` types from `database/sql` for better experience handling nullability.

Extra miles to integrate it with `sqlc` codegen workflow.
