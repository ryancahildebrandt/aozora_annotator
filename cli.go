// -*- coding: utf-8 -*-

// Created on Tue Apr 28 05:05:58 PM EDT 2026
// author: Ryan Hildebrandt, github.com/ryancahildebrandt

package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"strings"
	"text/template"

	"github.com/urfave/cli/v3"
)

var (
	uncommonOnly = cli.BoolFlag{
		Name:    "uncommon",
		Aliases: []string{"u"},
		Usage:   "Whether to exclude common terms from rendered annotations, as defined by the jotoba api",
	}
	kanjiOnly = cli.BoolFlag{
		Name:    "kanji",
		Aliases: []string{"k"},
		Usage:   "Whether to only render annotations for terms containing one or more kanji characters",
	}
	sizeStr = cli.StringFlag{
		Name:    "size",
		Aliases: []string{"s"},
		Usage:   "CSS string used to scale text size where applicable, either percent (125%), pixels (61px), or em (1.1em)",
		Value:   "100%",
	}
	workId = cli.StringArg{
		Name:      "id",
		UsageText: "render WORK_ID",
	}
	searchQuery = cli.StringArg{
		Name:      "search",
		UsageText: "search QUERY",
	}
)

// Processes one document with the given annotation style, file format, and size string
// outputs files with doc id and title
func RenderDoc(doc Document, annotations string, format string, size string) error {
	var (
		err     error
		outfile = fmt.Sprintf("./outputs/%v_%s_%s.%s", doc.ID, doc.Title, annotations, format)
		funcMap = template.FuncMap{
			"furigana": func(t string) string {
				return doc.Lookups[t].Furigana
			},
			"meaning": func(t string) string {
				return doc.Lookups[t].Meaning
			},
			"valid": func(t string) bool {
				return doc.Lookups[t].Valid
			},
			"annotationType": func() string {
				return annotations
			},
			"sizeString": func() string {
				return size
			},
			"replaceBreaks": func(t string) string {
				return strings.ReplaceAll(t, "\n", "<br>")
			},
		}
	)

	f, err := os.OpenFile(outfile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	w := bufio.NewWriter(f)

	templateFiles := fmt.Sprintf("./templates/*.%s.tmpl", format)
	tmpl, err := template.New(annotations).Funcs(funcMap).ParseGlob(templateFiles)
	if err != nil {
		return err
	}
	err = tmpl.ExecuteTemplate(w, annotations, doc)
	if err != nil {
		return err
	}
	log.Printf("Saved doc %v (%s by %s) to %s\n", doc.ID, doc.Title, doc.Author, outfile)

	return nil
}
