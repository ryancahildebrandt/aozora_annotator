// -*- coding: utf-8 -*-

// Created on Sun Apr 26 11:13:11 AM EDT 2026
// author: Ryan Hildebrandt, github.com/ryancahildebrandt

package main

import (
	"database/sql"
	"fmt"
	"os"
	"regexp"
	"slices"
	"text/tabwriter"

	"github.com/ikawaha/kagome-dict/ipa"
	"github.com/ikawaha/kagome/v2/tokenizer"
	_ "modernc.org/sqlite"
)

type SearchResult struct {
	作品ID     int
	作品名      string
	著者       string
	副題       string
	分類番号     string
	底本初版発行年1 string
}

// print search results to stdout, one per line
func PrintResults(res []SearchResult) {
	format := func(r SearchResult) string {
		return fmt.Sprintf("%v\t%s\t%s\t%s\t%s\t%s\t", r.作品ID, r.作品名, r.著者, r.副題, r.分類番号, r.底本初版発行年1)
	}

	w := tabwriter.NewWriter(os.Stdout, 1, 1, 1, '.', 0)
	fmt.Fprintln(w, "作品ID\t作品名\t著者\t副題\t分類番号\t底本初版発行年1\t")
	for _, r := range res {
		fmt.Fprintln(w, format(r))
	}
	w.Flush()
}

type AZBDatabase struct {
	*sql.DB
}

func NewAZBDatabase() (AZBDatabase, error) {
	dbfile := "./data/aozora_corpus.db"
	db, err := sql.Open("sqlite", dbfile)
	return AZBDatabase{db}, err
}

// finds documents with search term in the 作品ID (work id), 作品名 (title), 著者 (author), 副題 (subtitle), 分類番号 (genre code), 底本初版発行年1 (firstpublication date) fields
func (db *AZBDatabase) Search(search string) ([]SearchResult, error) {
	var (
		res       []SearchResult
		row       SearchResult
		baseQuery = `
	WITH authorsTable AS (
		SELECT
			著者,
			人物ID
		FROM
			authors
	)
	SELECT
		作品ID,
		作品名,
		著者,
		副題,
		分類番号,
		底本初版発行年1
	FROM
		works
		JOIN authorsTable USING (人物ID)
	WHERE
		作品ID LIKE '%%%v%%'
		OR 作品名 LIKE '%%%v%%'
		OR 著者 LIKE '%%%v%%'
		OR 副題 LIKE '%%%v%%'
		OR 分類番号 LIKE '%%%v%%'
		OR 底本初版発行年1 LIKE '%%%v%%'
	`
	)

	query := fmt.Sprintf(baseQuery, search, search, search, search, search, search)
	rows, err := db.Query(query)
	if err != nil {
		return res, err
	}
	defer rows.Close()

	for rows.Next() {
		err = rows.Scan(
			&row.作品ID,
			&row.作品名,
			&row.著者,
			&row.副題,
			&row.分類番号,
			&row.底本初版発行年1)
		if err != nil {
			return res, err
		}
		res = append(res, row)
	}

	return res, nil
}

// fetches the main text from the given work id
func (db *AZBDatabase) GetText(id string) (Document, error) {
	var (
		res       Document
		err       error
		baseQuery = `
	WITH authorsTable AS (
		SELECT
			著者,
			人物ID
		FROM
			authors
	),
	textsTable AS (
		SELECT
			作品ID,
			本文,
			本文字数
		FROM
			texts
		WHERE
			作品ID = %v
	)
	SELECT
		作品ID,
		作品名,
		著者,
		本文,
		本文字数
	FROM
		works
		JOIN authorsTable USING (人物ID)
		JOIN textsTable USING (作品ID)
	`
	)

	query := fmt.Sprintf(baseQuery, id)
	row := db.QueryRow(query, nil)
	err = row.Scan(
		&res.ID,
		&res.Title,
		&res.Author,
		&res.Text,
		&res.Length,
	)
	if err != nil {
		return res, err
	}

	return res, nil
}

// gets all available furigana reading information for the specified work id
func (db *AZBDatabase) GetFurigana(id string) (map[string]string, error) {
	processFurigana := func(rows *sql.Rows) (map[string]string, error) {
		var (
			out     = make(map[string]string)
			context string
			reading string
		)

		tok, err := tokenizer.New(ipa.Dict(), tokenizer.OmitBosEos())
		if err != nil {
			return out, err
		}

		for rows.Next() {
			err = rows.Scan(&context, &reading)
			if err != nil {
				return out, err
			}
			tokens := tok.Wakati(context)
			ind := slices.Index(tokens, "（")
			key := tokens[ind-1]
			val := regexp.MustCompile("[ぁ-んァ-ンヽゞゝ／″＼]+").FindString(reading)
			out[key] = val
		}
		return out, nil
	}

	var (
		err       error
		out       = make(map[string]string)
		baseQuery = `SELECT 前後関係, 振り仮名 FROM furigana WHERE 作品ID = ?`
	)

	query, err := db.Prepare(baseQuery)
	if err != nil {
		return out, err
	}
	rows, err := query.Query(id)
	if err != nil {
		return out, err
	}
	defer rows.Close()

	out, err = processFurigana(rows)
	if err != nil {
		return out, err
	}

	return out, nil
}
