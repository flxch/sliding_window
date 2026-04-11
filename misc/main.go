package main

import (
    "encoding/json"
    "fmt"
    "os"
    "strconv"
    "strings"
)

func main() {
    if len(os.Args) < 2 {
        printUsage()
        os.Exit(1)
    }

    switch os.Args[1] {
    case "extract":
        runExtract(os.Args[2:])
    case "remove":
        runRemove(os.Args[2:])
    case "field":
        runField(os.Args[2:])
    default:
        fmt.Fprintf(os.Stderr, "Error: unknown command %q\n\n", os.Args[1])
        printUsage()
        os.Exit(1)
    }
}

func printUsage() {
    fmt.Fprint(os.Stderr, `
Usage:
  simple-json-tool <command> [arguments] < input.json

Commands:
  extract   Extract JSON objects matching all given field=value pairs
  remove    Remove specified fields from the entire JSON tree
  field     Print the value and path of a field at a given depth level

Run 'simple-json-tool <command>' with no arguments for command-specific help.
`)
}

// ── extract ──────────────────────────────────────────────────────────────────

func runExtract(args []string) {
    if len(args) == 0 {
        fmt.Fprint(os.Stderr, `Usage:
  simple-json-tool extract -field=value [-field=value ...] < input.json

Arguments:
  Each argument is a -key=value pair used to identify the target object.
  All pairs must match (AND logic). Values are compared as strings.

Examples:
  simple-json-tool extract -id=42 < data.json
  simple-json-tool extract -name=Alice -role=admin < users.json
`)
        os.Exit(1)
    }

    matchers := map[string]string{}
    for _, arg := range args {
        arg = strings.TrimLeft(arg, "-")
        if idx := strings.Index(arg, "="); idx != -1 {
            matchers[arg[:idx]] = arg[idx+1:]
        } else {
            fmt.Fprintf(os.Stderr, "Error: argument %q is not in -key=value form\n", arg)
            os.Exit(1)
        }
    }

    root := decodeStdin()

    var results []interface{}
    extractSearch(root, matchers, &results)

    if len(results) == 0 {
        fmt.Fprintln(os.Stderr, "No matching object found.")
        os.Exit(1)
    }

    enc := newEncoder()
    for _, r := range results {
        enc.Encode(r)
    }
}

func extractSearch(node interface{}, matchers map[string]string, results *[]interface{}) {
    switch v := node.(type) {
    case map[string]interface{}:
        if extractMatches(v, matchers) {
            *results = append(*results, v)
            return
        }
        for _, child := range v {
            extractSearch(child, matchers, results)
        }
    case []interface{}:
        for _, item := range v {
            extractSearch(item, matchers, results)
        }
    }
}

func extractMatches(obj map[string]interface{}, matchers map[string]string) bool {
    for key, want := range matchers {
        got, ok := obj[key]
        if !ok || !extractValueMatches(got, want) {
            return false
        }
    }
    return true
}

func extractValueMatches(val interface{}, target string) bool {
    switch v := val.(type) {
    case string:
        return v == target
    case float64:
        return fmt.Sprintf("%v", v) == target || fmt.Sprintf("%.f", v) == target
    case bool:
        return fmt.Sprintf("%v", v) == target
    case nil:
        return target == "null"
    default:
        return false
    }
}

// ── remove ───────────────────────────────────────────────────────────────────

func runRemove(args []string) {
    if len(args) == 0 {
        fmt.Fprint(os.Stderr, `Usage:
  simple-json-tool remove <field> [field ...] < input.json

Arguments:
  One or more field names to remove from every object in the JSON tree.

Examples:
  simple-json-tool remove password < user.json
  simple-json-tool remove password secret token created_at < data.json
`)
        os.Exit(1)
    }

    remove := make(map[string]bool, len(args))
    for _, f := range args {
        remove[f] = true
    }

    result := removeStrip(decodeStdin(), remove)
    newEncoder().Encode(result)
}

func removeStrip(node interface{}, remove map[string]bool) interface{} {
    switch v := node.(type) {
    case map[string]interface{}:
        out := make(map[string]interface{}, len(v))
        for key, val := range v {
            if !remove[key] {
                out[key] = removeStrip(val, remove)
            }
        }
        return out
    case []interface{}:
        out := make([]interface{}, len(v))
        for i, item := range v {
            out[i] = removeStrip(item, remove)
        }
        return out
    default:
        return node
    }
}

// ── field ─────────────────────────────────────────────────────────────────────

func runField(args []string) {
    if len(args) != 2 {
        fmt.Fprint(os.Stderr, `Usage:
  simple-json-tool field <field> <level> < input.json

Arguments:
  field   The field name to search for.
  level   The nesting depth at which to look (root = 0).

Output:
  Each match is printed as:  <path>: <value>
  Array indices appear as [N], object keys as .key.

Examples:
  simple-json-tool field id 1 < data.json
  simple-json-tool field email 2 < users.json
`)
        os.Exit(1)
    }

    fieldName := args[0]
    level, err := strconv.Atoi(args[1])
    if err != nil || level < 0 {
        fmt.Fprintf(os.Stderr, "Error: level must be a non-negative integer, got %q\n", args[1])
        os.Exit(1)
    }

    found := false
    fieldWalk(decodeStdin(), fieldName, level, 0, "$", &found)

    if !found {
        fmt.Fprintf(os.Stderr, "No field %q found at level %d.\n", fieldName, level)
        os.Exit(1)
    }
}

func fieldWalk(node interface{}, field string, targetLevel, currentLevel int, path string, found *bool) {
    if currentLevel == targetLevel {
        obj, ok := node.(map[string]interface{})
        if !ok {
            return
        }
        val, exists := obj[field]
        if !exists {
            return
        }
        *found = true
        fmt.Printf("%s.%s: %s\n", path, field, fieldFormatValue(val))
        return
    }

    switch v := node.(type) {
    case map[string]interface{}:
        for key, child := range v {
            fieldWalk(child, field, targetLevel, currentLevel+1, path+"."+key, found)
        }
    case []interface{}:
        for i, item := range v {
            fieldWalk(item, field, targetLevel, currentLevel+1, fmt.Sprintf("%s[%d]", path, i), found)
        }
    }
}

func fieldFormatValue(val interface{}) string {
    switch v := val.(type) {
    case string:
        return v
    case float64:
        if v == float64(int64(v)) {
            return strconv.FormatInt(int64(v), 10)
        }
        return strconv.FormatFloat(v, 'f', -1, 64)
    case bool:
        return strconv.FormatBool(v)
    case nil:
        return "null"
    default:
        b, _ := json.Marshal(v)
        return strings.TrimSpace(string(b))
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────

func decodeStdin() interface{} {
    var root interface{}
    if err := json.NewDecoder(os.Stdin).Decode(&root); err != nil {
        fmt.Fprintf(os.Stderr, "Error parsing JSON input: %v\n", err)
        os.Exit(1)
    }
    return root
}

func newEncoder() *json.Encoder {
    enc := json.NewEncoder(os.Stdout)
    enc.SetIndent("", "  ")
    return enc
}
