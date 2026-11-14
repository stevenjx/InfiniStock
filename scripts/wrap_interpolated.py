#!/usr/bin/env python3
"""把 "…\\(expr)…" 改写成 String(localized:) 的参数化形式。

为什么必须改：Xcode 的 String Catalog 只能从 `String(localized:)` 里提取
带参数的字符串。裸插值 `"共 \\(n) 台"` 到运行时已经是一段拼好的文本，
catalog 里查不到，英文界面会原样显示中文。

改写规则（只处理单个插值的字符串，多插值的需人工判断语序）：
    Text("共 \\(rows.count) 台")
→   Text(String(localized: "共 \\(rows.count) 台"))

`String(localized:)` 接受插值，并在编译期把它转成一个 %lld 占位符连同
原始格式一起交给本地化查找——翻译里可以自由调整占位符顺序。
"""
import re
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "InfiniStock"

# 已经是 localizable 上下文的调用，不重复包
WRAPPED = re.compile(r'String\(localized:')

def transform_line(line: str) -> str:
    if line.lstrip().startswith("//"):
        return line

    out = []
    i = 0
    n = len(line)
    changed = False

    while i < n:
        # 找字符串起始引号（跳过已有的 #"..."# 原始串与非字符串区域）
        if line[i] != '"':
            out.append(line[i])
            i += 1
            continue

        # 判断这一行里，这个字面量前面紧邻的是不是 String(localized:
        prefix = "".join(out)
        if re.search(r'String\(localized:\s*$', prefix):
            # 已经包好了，原样拷贝整段字面量
            j = i + 1
            while j < n:
                if line[j] == '\\':
                    j += 2
                    continue
                if line[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(line[i:j])
            i = j
            continue

        # 读出整个字面量（含转义）
        j = i + 1
        while j < n:
            if line[j] == '\\':
                j += 2
                continue
            if line[j] == '"':
                break
            j += 1
        if j >= n:
            out.append(line[i:])
            break

        body = line[i + 1:j]
        literal = line[i:j + 1]

        has_cjk = re.search(r'[\u4e00-\u9fff]', body) is not None
        interps = re.findall(r'\\\(', body)

        # 只处理：含中文 + 恰好一个插值 + 不在注释里
        if has_cjk and len(interps) == 1:
            out.append(f"String(localized: {literal})")
            changed = True
        else:
            out.append(literal)

        i = j + 1

    return "".join(out)


def main():
    total = 0
    for path in sorted(ROOT.rglob("*.swift")):
        src = path.read_text(encoding="utf-8")
        lines = src.split("\n")
        out_lines = []
        file_changed = 0
        for line in lines:
            new = transform_line(line)
            if new != line:
                file_changed += 1
            out_lines.append(new)
        if file_changed:
            path.write_text("\n".join(out_lines), encoding="utf-8")
            print(f"{file_changed:3d}  {path.relative_to(ROOT.parent)}")
            total += file_changed
    print(f"\n共改写 {total} 处")


if __name__ == "__main__":
    main()
