-- name: GetIndividual :one
SELECT * FROM individuals
WHERE id = $1 LIMIT 1;
