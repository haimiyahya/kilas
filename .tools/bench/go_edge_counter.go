// Counts kilas-style graph edges in a Go repo via AST analysis.
// CALLS edges = distinct (caller, callee) internal function call pairs.
// Usage: go run go_edge_counter.go <repo-root>
package main

import (
	"bufio"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type pkgInfo struct {
	path     string              // import path (module-relative)
	funcDecls map[string]bool    // top-level func names (incl. methods, name-only)
}

type callKey struct{ src, dst string }

var (
	skipDirs  = map[string]bool{"vendor": true, "_archived": true, "_disabled": true, "testdata": true}
	module    string
	pkgs      = map[string]*pkgInfo{} // import path -> info
	files     []string
	typeEdges = map[string]int{} // IMPORTS: caller pkg -> callee pkg (internal only)
	callSites  int
	extCalls   int
	methodCalls int
)

func importPath(dir, root string) string {
	rel, err := filepath.Rel(root, dir)
	if err != nil || rel == "." {
		return module
	}
	return module + "/" + filepath.ToSlash(rel)
}

func topDir(dir, root string) string {
	rel, err := filepath.Rel(root, dir)
	if err != nil {
		return "?"
	}
	parts := strings.Split(filepath.ToSlash(rel), "/")
	if parts[0] == "." {
		return "(root)"
	}
	return parts[0]
}

func main() {
	root := os.Args[1]

	// read module path from go.mod
	fm, err := os.Open(filepath.Join(root, "go.mod"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "no go.mod:", err)
		os.Exit(1)
	}
	sc := bufio.NewScanner(fm)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(line, "module ") {
			module = strings.Fields(line)[1]
			break
		}
	}
	fm.Close()

	// pass 1: collect files + declared funcs per package
	filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || !d.IsDir() {
			if !d.IsDir() && strings.HasSuffix(path, ".go") {
				files = append(files, path)
			}
			return nil
		}
		if skipDirs[d.Name()] && path != root {
			return filepath.SkipDir
		}
		return nil
	})

	for _, f := range files {
		isTest := strings.HasSuffix(f, "_test.go")
		af, err := parser.ParseFile(token.NewFileSet(), f, nil, parser.SkipObjectResolution)
		if err != nil {
			continue
		}
		ip := importPath(filepath.Dir(f), root)
		p, ok := pkgs[ip]
		if !ok {
			p = &pkgInfo{path: ip, funcDecls: map[string]bool{}}
			pkgs[ip] = p
		}
		if !isTest {
			for _, d := range af.Decls {
				if fd, ok := d.(*ast.FuncDecl); ok {
					p.funcDecls[fd.Name.Name] = true
				}
			}
		}
	}

	// pass 2: resolve call sites
	edgesByDir := map[string]map[callKey]bool{}
	type testStat struct{ testFuncs, coveredPkgs int }
	testFuncs := 0
	totalEdges := map[callKey]bool{}
	nodeIDs := map[string]bool{}

	for _, f := range files {
		isTest := strings.HasSuffix(f, "_test.go")
		af, err := parser.ParseFile(token.NewFileSet(), f, nil, parser.SkipObjectResolution)
		if err != nil {
			continue
		}
		ip := importPath(filepath.Dir(f), root)
		p := pkgs[ip]
		td := topDir(filepath.Dir(f), root)

		// file import map: qualifier -> import path
		alias := map[string]string{}
		for _, imp := range af.Imports {
			path := strings.Trim(imp.Path.Value, `"`)
			name := ""
			if imp.Name != nil {
				name = imp.Name.Name
			} else {
				name = path[strings.LastIndex(path, "/")+1:]
			}
			alias[name] = path
		}

		if isTest {
			for _, d := range af.Decls {
				if fd, ok := d.(*ast.FuncDecl); ok && strings.HasPrefix(fd.Name.Name, "Test") {
					testFuncs++
				}
			}
		}

		ast.Inspect(af, func(n ast.Node) bool {
			fd, ok := n.(*ast.FuncDecl)
			if !ok {
				return true
			}
			if isTest {
				return false // don't count test-internal calls as CALLS edges
			}
			src := ip + "." + fd.Name.Name
			nodeIDs[src] = true

			ast.Inspect(fd.Body, func(c ast.Node) bool {
				ce, ok := c.(*ast.CallExpr)
				if !ok {
					return true
				}
				callSites++
				switch fn := ce.Fun.(type) {
				case *ast.Ident:
					if p.funcDecls[fn.Name] {
						dst := ip + "." + fn.Name
						totalEdges[callKey{src, dst}] = true
						if edgesByDir[td] == nil {
							edgesByDir[td] = map[callKey]bool{}
						}
						edgesByDir[td][callKey{src, dst}] = true
					} else {
						extCalls++
					}
				case *ast.SelectorExpr:
					if q, ok := fn.X.(*ast.Ident); ok {
						path, known := alias[q.Name]
						if known && strings.HasPrefix(path, module+"/") {
							calleePkg := pkgs[path]
							if calleePkg != nil && calleePkg.funcDecls[fn.Sel.Name] {
								dst := path + "." + fn.Sel.Name
								totalEdges[callKey{src, dst}] = true
								if edgesByDir[td] == nil {
									edgesByDir[td] = map[callKey]bool{}
								}
								edgesByDir[td][callKey{src, dst}] = true
							}
						} else {
							extCalls++
							if !known {
								methodCalls++ // method call on a value: type info needed to resolve
							}
						}
					} else {
						methodCalls++
					}
				}
				return true
			})
			return false
		})
	}

	// internal IMPORTS edges: distinct (pkgA imports pkgB) via file imports — recompute cheaply
	for _, f := range files {
		af, err := parser.ParseFile(token.NewFileSet(), f, nil, parser.SkipObjectResolution)
		if err != nil || strings.HasSuffix(f, "_test.go") {
			continue
		}
		ip := importPath(filepath.Dir(f), root)
		for _, imp := range af.Imports {
			path := strings.Trim(imp.Path.Value, `"`)
			if strings.HasPrefix(path, module+"/") {
				typeEdges[ip+" -> "+path]++
			}
		}
	}

	loc, testLoc := 0, 0
	for _, f := range files {
		n := countLines(f)
		if strings.HasSuffix(f, "_test.go") {
			testLoc += n
		} else {
			loc += n
		}
	}

	fmt.Printf("== %s ==\n", root)
	fmt.Printf("module: %s\n", module)
	fmt.Printf("files: %d  |  src LOC: %d  |  test LOC: %d\n", len(files), loc, testLoc)
	fmt.Printf("packages: %d\n", len(pkgs))
	fmt.Printf("function nodes (non-test decls touched): %d distinct\n", len(nodeIDs))
	fmt.Printf("call sites: %d total  |  %d external/unresolved  |  %d method calls (unresolved, type info needed)\n", callSites, extCalls, methodCalls)
	fmt.Printf("CALLS edges (distinct caller->callee pairs): %d\n", len(totalEdges))
	fmt.Printf("IMPORTS edges (distinct pkg->pkg, internal): %d\n", len(typeEdges))
	fmt.Printf("test functions: %d\n", testFuncs)
	fmt.Println("\n-- CALLS edges by caller's top-level dir --")
	var dirs []string
	for d := range edgesByDir {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)
	for _, d := range dirs {
		fmt.Printf("  %-12s %5d edges\n", d, len(edgesByDir[d]))
	}
}

func countLines(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	n := 0
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	for sc.Scan() {
		n++
	}
	return n
}
