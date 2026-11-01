package main

import (
	_ "embed"
	"fmt"
	"strings"
)

//go:embed VERSION
var version string

func main() {
	fmt.Println(strings.TrimSpace(version))
}
