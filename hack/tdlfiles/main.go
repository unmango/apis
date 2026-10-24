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
	"io/fs"
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
		// A missing dir lists nothing, as $(wildcard) would.
		_ = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || filepath.Ext(path) != ".tdl" {
				return nil
			}
			if rel, err := filepath.Rel(root, path); err == nil {
				files = append(files, filepath.ToSlash(rel))
			}
			return nil
		})
	}
	slices.Sort(files)
	return strings.Join(slices.Compact(files), " ")
}
