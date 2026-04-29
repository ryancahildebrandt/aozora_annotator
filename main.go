// -*- coding: utf-8 -*-

// Created on Sun Apr 26 10:56:28 AM EDT 2026
// author: Ryan Hildebrandt, github.com/ryancahildebrandt

package main

import (
	"context"
	"errors"
	"log"
	"os"

	"github.com/urfave/cli/v3"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	var err error
	var app = &cli.Command{
		Name:                  "Aozora Annotator",
		Usage:                 "AozoraBunko Annotator Script",
		UsageText:             "aozora_annotator [COMMAND] [OPTIONS] [ARGS]",
		EnableShellCompletion: true,
		Suggest:               true,
		DefaultCommand:        "render",
		Commands: []*cli.Command{
			{
				Name:                  "search",
				UsageText:             "aozora_annotator search [QUERY]",
				Usage:                 "Find texts matching search query in the title, id, author, or genre fields",
				EnableShellCompletion: true,
				Suggest:               true,
				Flags:                 []cli.Flag{},
				Arguments:             []cli.Argument{&searchQuery},
				Action: func(ctx context.Context, cmd *cli.Command) error {
					if searchQuery.Get().(string) == "" {
						return errors.New("please provide a search term")
					}
					db, err := NewAZBDatabase()
					if err != nil {
						return err
					}
					res, err := db.Search(searchQuery.Get().(string))
					if err != nil {
						return err
					}
					PrintResults(res)

					return nil
				},
			},
			{
				Name:                  "render",
				UsageText:             "aozora_annotator render [OPTIONS] [ID]",
				Usage:                 "Create annotated html and plain text files for provided work id",
				EnableShellCompletion: true,
				Suggest:               true,
				Flags: []cli.Flag{
					&sizeStr,
					&uncommonOnly,
					&kanjiOnly,
				},
				Arguments: []cli.Argument{&workId},
				Action: func(ctx context.Context, cmd *cli.Command) error {
					if workId.Get().(string) == "" {
						return errors.New("please provide a work id")
					}

					db, err := NewAZBDatabase()
					if err != nil {
						return err
					}
					doc, err := db.GetText(workId.Get().(string))
					if err != nil {
						return err
					}
					doc.Furigana, err = db.GetFurigana(workId.Get().(string))
					if err != nil {
						return err
					}
					doc.Lookups, err = PopulateLookups(doc)
					if err != nil {
						return err
					}
					err = SaveLookups(doc)
					if err != nil {
						return err
					}
					doc.Sentences = SplitSentences(doc.Text)
					for i := range doc.Sentences {
						doc.Sentences[i].Tokens = SplitTokens(doc.Sentences[i].Text)
					}
					if uncommonOnly.Value {
						doc.Lookups = RemoveCommon(doc.Lookups)
					}
					if kanjiOnly.Value {
						doc.Lookups = RemoveKanaOnly(doc.Lookups)
					}
					for _, job := range [][]string{
						{"alternating", "txt"},
						{"layered", "txt"},
						{"unannotated", "txt"},
						{"alternating", "html"},
						{"layered", "html"},
						{"parallel", "html"},
						{"sidebyside", "html"},
						{"unannotated", "html"},
					} {
						err = RenderDoc(doc, job[0], job[1], sizeStr.Value)
						if err != nil {
							return err
						}
					}
					return nil
				},
			},
		},
	}

	err = app.Run(context.Background(), os.Args)
	if err != nil {
		log.Fatal(err)
	}
}
