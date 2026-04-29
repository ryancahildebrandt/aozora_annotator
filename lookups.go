// -*- coding: utf-8 -*-

// Created on Sun Apr 26 11:00:10 AM EDT 2026
// author: Ryan Hildebrandt, github.com/ryancahildebrandt

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"slices"
	"strings"

	"github.com/ikawaha/kagome-dict/ipa"
	"github.com/ikawaha/kagome/v2/tokenizer"
	"github.com/schollz/progressbar/v3"
)

type JotobaRequestBody struct {
	Query     string `json:"query"`
	Language  string `json:"language"`
	NoEnglish bool   `json:"no_english"`
}

type JotobaResponseBody struct {
	Kanji []struct {
		Chinese     []string `json:"chinese"`
		Frequency   int64    `json:"frequency"`
		Grade       int64    `json:"grade"`
		Jlpt        int64    `json:"jlpt"`
		KoreanH     []string `json:"korean_h"`
		KoreanR     []string `json:"korean_r"`
		Kunyomi     []string `json:"kunyomi"`
		Literal     string   `json:"literal"`
		Meanings    []string `json:"meanings"`
		Onyomi      []string `json:"onyomi"`
		Parts       []string `json:"parts"`
		Radical     string   `json:"radical"`
		StrokeCount int64    `json:"stroke_count"`
		Variant     []string `json:"variant"`
	} `json:"kanji"`
	Words []struct {
		Audio  string `json:"audio"`
		Common bool   `json:"common"`
		Pitch  []struct {
			High bool   `json:"high"`
			Part string `json:"part"`
		} `json:"pitch"`
		Reading struct {
			Furigana string `json:"furigana"`
			Kana     string `json:"kana"`
			Kanji    string `json:"kanji"`
		} `json:"reading"`
		Senses []struct {
			Glosses     []string `json:"glosses"`
			Information string   `json:"information"`
			Language    string   `json:"language"`
			Pos         []any    `json:"pos"`
		} `json:"senses"`
	} `json:"words"`
}

// returns an error if the search term is empty or consists of exactly 1 non-kanji character
func checkQuery(query string) error {
	if query == "" {
		return errors.New("empty query")
	}
	if regexp.MustCompile("^[ぁ-んァ-ン\u3000-\u303Fa-zA-Z0-9_]$").MatchString(query) {
		return errors.New("single non-kanji character query")
	}
	return nil

}

func newRequest(query string) (*http.Request, error) {
	buf, err := json.Marshal(JotobaRequestBody{
		Query:     query,
		Language:  "English",
		NoEnglish: false,
	})
	if err != nil {
		log.Fatal(err)
	}

	req, err := http.NewRequest(
		"POST",
		"https://jotoba.de/api/search/words",
		bytes.NewReader(buf),
	)
	if err != nil {
		log.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	return req, nil
}

func handleRequest(req *http.Request) (JotobaResponseBody, error) {
	var res JotobaResponseBody
	var err error

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return res, err
	}
	defer resp.Body.Close()

	err = json.NewDecoder(resp.Body).Decode(&res)
	if err != nil {
		return res, err
	}

	if len(res.Words) == 0 {
		return res, fmt.Errorf("no results for term")
	}

	return res, nil
}

type WordLookup struct {
	Term     string
	Common   bool
	Kana     string
	Kanji    string
	Furigana string
	Meaning  string
	Info     string
	Valid    bool
}

// creates a new word lookup from jotoba response, selecting the word entry that matches the target reading if possible
func NewWordLookup(word string, resp JotobaResponseBody, reading string) WordLookup {
	var ind int

	for i, word := range resp.Words {
		if strings.Contains(word.Reading.Kana, reading) {
			ind = i
			break
		}
	}

	return WordLookup{
		Term:     word,
		Common:   resp.Words[ind].Common,
		Kana:     resp.Words[ind].Reading.Kana,
		Kanji:    resp.Words[ind].Reading.Kanji,
		Furigana: resp.Words[ind].Reading.Furigana,
		Meaning:  fmt.Sprint(resp.Words[ind].Senses[0].Glosses),
		Info:     resp.Words[ind].Senses[0].Information,
		Valid:    true,
	}
}

// fetch all lookups for a given doc from jotoba api
func LookupTokens(doc Document) (map[string]WordLookup, error) {
	var out = make(map[string]WordLookup)
	var err error

	tok, err := tokenizer.New(ipa.Dict(), tokenizer.OmitBosEos())
	if err != nil {
		return out, err
	}
	tokens := tok.Wakati(doc.Text)
	slices.Sort(tokens)
	tokens = slices.Compact(tokens)
	bar := NewBar(len(tokens), "Token lookups")

	for _, t := range tokens {
		err = checkQuery(t)
		if err != nil {
			bar.Add(1)
			continue
		}
		req, err := newRequest(t)
		if err != nil {
			return out, err
		}
		resp, err := handleRequest(req)
		if err != nil {
			log.Println(err)
			continue
		}
		lookup := NewWordLookup(t, resp, doc.Furigana[t])
		out[t] = lookup

		bar.Add(1)
	}

	return out, nil
}

// write lookups to json with doc-specific file name
func SaveLookups(doc Document) error {
	var (
		err     error
		outFile = fmt.Sprintf("./data/%v_%s.json", doc.ID, doc.Title)
	)

	f, err := os.OpenFile(outFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}

	err = json.NewEncoder(f).Encode(doc.Lookups)
	if err != nil {
		return err
	}

	return err
}

// read lookups from on-disk json
func LoadLookups(doc Document) (map[string]WordLookup, error) {
	var (
		err        error
		buf        []byte
		lookupFile = fmt.Sprintf("./data/%v_%s.json", doc.ID, doc.Title)
		out        = make(map[string]WordLookup)
	)

	f, err := os.Open(lookupFile)
	if err != nil {
		return out, err
	}
	defer f.Close()

	buf, err = io.ReadAll(f)
	if err != nil {
		return out, err
	}
	err = json.Unmarshal(buf, &out)

	return out, err
}

// adds lookups to doc, checking for lookups json file on disk before fetching from jotoba
func PopulateLookups(doc Document) (map[string]WordLookup, error) {
	var err error
	var out = make(map[string]WordLookup)

	out, err = LoadLookups(doc)
	if err == nil {
		return out, nil
	}

	out, err = LookupTokens(doc)
	if err != nil {
		return out, err
	}

	return out, nil
}

// basic progress bar for lookup requests
func NewBar(n int, desc string) *progressbar.ProgressBar {
	return progressbar.NewOptions(
		n,
		progressbar.OptionFullWidth(),
		progressbar.OptionOnCompletion(func() { fmt.Println() }),
		progressbar.OptionEnableColorCodes(true),
		progressbar.OptionSetElapsedTime(false),
		progressbar.OptionSetPredictTime(true),
		progressbar.OptionShowCount(),
		progressbar.OptionShowElapsedTimeOnFinish(),
		progressbar.OptionSetDescription(desc),
		progressbar.OptionSetTheme(progressbar.Theme{
			Saucer:        "[light_magenta]=[reset]",
			SaucerHead:    "[light_magenta]>[reset]",
			SaucerPadding: " ",
			BarStart:      "[",
			BarEnd:        "]",
		}),
	)
}
