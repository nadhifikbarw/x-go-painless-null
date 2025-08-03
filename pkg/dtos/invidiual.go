package dtos

import (
	"github.com/guregu/null/v6"
	"github.com/jackc/pgx/v5/pgtype"
)

// Imagine you have Web UI stepped form
// allowing user to correct their uinfin and names
type UinfinNamesForm struct {
	Uinfin            string
	Name              null.String
	Aliasnme          null.String
	HanyupinName      null.String
	HanyupinAliasname null.String
	MarriedName       null.String
}

// Using pgtype

type PgUinfinNamesForm struct {
	Uinfin            string
	Name              pgtype.Text
	Aliasnme          pgtype.Text
	HanyupinName      pgtype.Text
	HanyupinAliasname pgtype.Text
	MarriedName       pgtype.Text
}

// Very leaky
type PgAgeForm struct {
	Age pgtype.Int4
}
