// -*- coding: utf-8 -*-

// Created on Sun Apr 26 11:12:00 AM EDT 2026
// author: Ryan Hildebrandt, github.com/ryancahildebrandt

package main

import (
	"regexp"

	"github.com/ikawaha/kagome-dict/ipa"
	"github.com/ikawaha/kagome/v2/tokenizer"
)

type Document struct {
	ID        int
	Title     string
	Author    string
	Text      string
	Length    int
	Lookups   map[string]WordLookup
	Furigana  map[string]string
	Sentences []Sentence
}

type Sentence struct {
	Text   string
	Tokens []string
}

func SplitSentences(text string) []Sentence {
	var out []Sentence
	for _, s := range regexp.MustCompile("([。！？])").Split(text, -1) {
		out = append(out, Sentence{Text: s})
	}
	return out
}

func SplitTokens(text string) []string {
	tok, _ := tokenizer.New(ipa.Dict(), tokenizer.OmitBosEos())
	return tok.Wakati(text)
}

// removes lookups for terms marked "Common" by jotoba
func RemoveCommon(lookups map[string]WordLookup) map[string]WordLookup {
	for k, v := range lookups {
		if v.Common {
			delete(lookups, k)
		}
	}

	return lookups
}

// removes lookups for terms without any kanji
func RemoveKanaOnly(lookups map[string]WordLookup) map[string]WordLookup {
	for k, v := range lookups {
		if regexp.MustCompile("[一-龯]").MatchString(v.Term) {
			delete(lookups, k)
		}
	}
	return lookups
}
