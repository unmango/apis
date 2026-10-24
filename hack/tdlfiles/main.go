//go:build makeplugin

// Command tdlfiles is a GNU make loadable object defining $(tdl-files dir...),
// which lists the .tdl files under each dir, sorted, as paths relative to the
// directory of the makefile that loaded it.
package main

/*
#include <gnumake.h>
*/
import "C"

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/unmango/go-gmk"
)

func main() {}

// root is the loading makefile's directory. The setup function runs while
// make reads the load directive, so that makefile is the last one listed.
var root string

//export tdlfiles_gmk_setup
func tdlfiles_gmk_setup(*C.gmk_floc) C.int {
	root = gmk.Expand("$(abspath $(dir $(lastword $(MAKEFILE_LIST))))")
	gmk.AddFunction("tdl-files", tdlFiles, 1, 0, gmk.FuncDefault)
	return 1
}

func tdlFiles(_ string, args []string) string {
	var files []string
	for _, dir := range strings.Fields(strings.Join(args, " ")) {
		if !filepath.IsAbs(dir) {
			dir = filepath.Join(root, dir)
		}
		err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() || filepath.Ext(path) != ".tdl" {
				return nil
			}
			rel, err := filepath.Rel(root, path)
			files = append(files, filepath.ToSlash(rel))
			return err
		})
		// A missing dir lists nothing, as $(wildcard) would. Any other error
		// lists nothing at all rather than part of the tree, so the Makefile
		// falls back to find, which reports it.
		if err != nil && !(errors.Is(err, fs.ErrNotExist) && errors.Is(statErr(dir), fs.ErrNotExist)) {
			return ""
		}
	}
	slices.Sort(files)
	return strings.Join(slices.Compact(files), " ")
}

func statErr(path string) error {
	_, err := os.Lstat(path)
	return err
}
