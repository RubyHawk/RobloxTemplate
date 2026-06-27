from pathlib import Path
import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_skill.py <skill-directory>")
        return 2

    directory = Path(sys.argv[1])
    skill_file = directory / "SKILL.md"
    if not skill_file.is_file():
        print(f"missing {skill_file}")
        return 1

    text = skill_file.read_text(encoding="utf-8")
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not match:
        print("SKILL.md must start with YAML frontmatter")
        return 1

    fields = {}
    for line in match.group(1).splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()

    if set(fields) != {"name", "description"}:
        print("frontmatter must contain only name and description")
        return 1
    if fields["name"] != directory.name or not re.fullmatch(r"[a-z0-9-]{1,63}", fields["name"]):
        print("skill name is invalid or differs from its directory")
        return 1
    if len(fields["description"]) < 40:
        print("skill description is too short to trigger reliably")
        return 1

    print(f"validated {skill_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
