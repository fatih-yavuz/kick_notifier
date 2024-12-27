#!/usr/bin/env python3

import argparse
from pathlib import Path
import sys
import subprocess
import json

EXCLUDED_DIRS = list(
    set(
        [
            ".git",
            "node_modules",
            ".vscode",
            ".next",
            ".pytest_cache",
            "build",
            ".idea",
            ".dart_tool",
            "ios",
            "android",
            "web",
            "macos",
        ]
    )
)
EXCLUDED_FILES = list(
    set(
        [
            ".cursorrules",
            ".cursorrules-template",
            "cursorruler.py",
            ".d.ts",
            ".tool-versions",
            ".lock",
            ".env",
            ".g.dart",
            ".g.yaml",
            ".g.json",
            ".freezed.dart",
            ".arb",
            "README.md",
        ]
    )
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Combines specified file types into a single file with headers"
    )
    parser.add_argument(
        "output_file",
        nargs="?",
        default="combined_output.txt",
        help="Output file path (default: combined_output.txt)",
    )
    return parser.parse_args()


def process_file_content(file: Path, content: str) -> str:
    """Process file content based on file type."""
    file_ext = file.suffix.lower()

    if file_ext in [".dart", ".yaml", ".json"]:
        # Remove comments, newlines, and excessive whitespace
        lines = []
        in_multiline_comment = False
        in_string = False
        string_char = None
        buffer = []
        i = 0

        while i < len(content):
            # Handle multi-line comments
            if content[i : i + 2] == "/*" and not in_string:
                in_multiline_comment = True
                i += 2
                continue
            elif content[i : i + 2] == "*/" and in_multiline_comment:
                in_multiline_comment = False
                i += 2
                continue
            elif in_multiline_comment:
                i += 1
                continue

            # Handle single-line comments
            if content[i : i + 2] == "//" and not in_string:
                while i < len(content) and content[i] != "\n":
                    i += 1
                continue

            # Handle strings
            if content[i] in ['"', "'", "`"] and (i == 0 or content[i - 1] != "\\"):
                if not in_string:
                    in_string = True
                    string_char = content[i]
                elif content[i] == string_char:
                    in_string = False
                buffer.append(content[i])
                i += 1
                continue

            # Handle whitespace
            if content[i].isspace() and not in_string:
                if buffer and not buffer[-1].isspace():
                    buffer.append(" ")
                i += 1
                continue

            buffer.append(content[i])
            i += 1

        return "".join(buffer).strip()

    elif file_ext == ".json":
        try:
            return json.dumps(json.loads(content), separators=(",", ":"))
        except json.JSONDecodeError:
            print(f"Warning: Could not parse JSON file {file}")
            return content

    return content


def main():
    args = parse_args()

    # Get script and output paths
    script_path = Path(__file__).resolve()
    output_path = Path(args.output_file).resolve()

    # File patterns
    include_patterns = [
        "**/*.dart",
        "**/*.yaml",
        "**/*.ts",
        "**/*.tsx",
        "**/*.json",
        "**/*.js",
        "**/*.jsx",
        "**/*.md",
        "**/*.html",
        "**/*.css",
        "**/*.scss",
        "**/*.less",
        "**/*.styl",
    ]

    exclude_patterns = [
        "**/Makefile",
        "**/*.md",
        "**/*.txt",
        ".vscode/**",
        "**/node_modules/**",  # Modified to exclude all nested files
        "**/.git/**",  # Modified to exclude all nested files
        "**/.cursorrules",
        "**/.cursorrules-template",
        "**/*.txt",
        "**/*.env",  # Environment files
        "**/*.pem",  # Certificate files
        "**/*.pub",  # Public key files
        "**/*.tfstate",  # Terraform state files
        "**/*.tfstate.backup",  # Terraform state backup files
        "**/*.tfplan",  # Terraform plan files
        "**/*.tfplan.json",  # Terraform plan JSON files
        "build/**",
        "**/build/**",
        "ios",
        "android",
        "web",
        "macos",
    ]

    # Display configuration
    print("Configuration:")
    print(f" Output file: {output_path}")
    print(f" Including: {', '.join(include_patterns)}")
    print(f" Excluding: {', '.join(exclude_patterns)}")

    print("\nGenerating file tree...\n")

    # First get all excluded files
    excluded_files = set()
    for pattern in exclude_patterns:
        excluded_files.update(Path().glob(pattern))

    # Then get matching files and remove excluded ones
    matching_files = set()
    for pattern in include_patterns:
        for file in Path().glob(pattern):
            if file not in excluded_files:
                matching_files.add(file)

    # Remove script itself and output file
    matching_files.discard(script_path)
    matching_files.discard(output_path)

    # Generate and display tree output
    tree_output = generate_tree()
    print(tree_output)

    print("\nStarting file combination...\n")

    # Process files
    processed_count = 0
    with open(output_path, "w") as outfile:
        # Write tree as a variable instead of raw output
        outfile.write("<project-tree>\n")
        outfile.write(tree_output + "\n")
        outfile.write("</project-tree>\n")
        outfile.write("<codebase>\n")

        for file in sorted(matching_files):
            if any(pattern in str(file) for pattern in EXCLUDED_DIRS + EXCLUDED_FILES):
                continue
            print(f"Processing: {file}")
            outfile.write(f"\n=== {file} ===\n\n")
            try:
                with open(file, "r") as infile:
                    content = infile.read()
                    processed_content = process_file_content(file, content)
                    outfile.write(processed_content)
                processed_count += 1
            except Exception as e:
                print(f"Error processing {file}: {e}")

        outfile.write("\n</codebase>")

    # Summary
    print("\nSummary:")
    print(f" Files processed: {processed_count}")
    print(f" Output location: {output_path}")
    print(f" Total size: {output_path.stat().st_size} bytes")

    # Post-processing
    print("\nPerforming post-processing...")
    try:
        # Read the combined output
        with open(output_path, "r") as f:
            combined_content = f.read()

        # Copy template and replace content
        template_path = Path(".cursorrules-template")
        rules_path = Path(".cursorrules")

        if not template_path.exists():
            print(f"Error: Template file '{template_path}' not found.")
            sys.exit(1)

        with open(template_path, "r") as f:
            template_content = f.read()

        final_content = template_content.replace("${CODEBASE}", combined_content)

        with open(rules_path, "w") as f:
            f.write(final_content)

        # Remove the temporary combined output
        output_path.unlink()

        print("Post-processing completed successfully:")
        print(f" - Created: {rules_path}")
        print(f" - Removed: {output_path}")

    except Exception as e:
        print(f"Error during post-processing: {e}")
        sys.exit(1)


def generate_tree():
    try:
        result = subprocess.run(
            [
                "tree",
                "--noreport",
                "-I",
                "node_modules|.git|.vscode|build|ios|android|web",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return result.stdout.strip()  # Ensure we return a valid string
    except FileNotFoundError:
        pass

    # Fall back to simple directory traversal
    tree_output = ["."]
    for path in sorted(Path().rglob("*")):
        if path.is_file() and not any(
            pattern in str(path) for pattern in [".git", "node_modules", ".vscode"]
        ):
            depth = len(path.parts) - 1
            tree_output.append("    " * depth + "├── " + path.name)
    return "\n".join(tree_output)


if __name__ == "__main__":
    main()
