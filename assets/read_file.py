# -*- coding: utf-8 -*-
"""read_file.py · 提取文件文本（供桌宠“文件拖拽”功能）

用法: python read_file.py <文件路径>
输出: JSON {"ok": true, "name": "文件名", "ext": ".docx", "text": "正文…", "chars": 1234}
支持: .docx (python-docx) / .pdf (PyMuPDF) / .txt .md .log .csv (直读)
"""
import json
import os
import sys


def read_docx(path):
    from docx import Document
    doc = Document(path)
    parts = []
    for p in doc.paragraphs:
        if p.text and p.text.strip():
            parts.append(p.text.strip())
    # 表格内容也带上
    for table in doc.tables:
        for row in table.rows:
            cells = [c.text.strip() for c in row.cells if c.text and c.text.strip()]
            if cells:
                parts.append(' | '.join(cells))
    return '\n'.join(parts)


def read_pdf(path):
    import fitz  # PyMuPDF
    doc = fitz.open(path)
    parts = []
    for page in doc:
        t = page.get_text()
        if t and t.strip():
            parts.append(t.strip())
    doc.close()
    return '\n'.join(parts)


def read_text(path):
    for enc in ('utf-8', 'gbk', 'utf-16'):
        try:
            with open(path, 'r', encoding=enc) as fh:
                return fh.read()
        except Exception:
            continue
    return ''


def main():
    path = sys.argv[1]
    ext = os.path.splitext(path)[1].lower()
    name = os.path.basename(path)
    text = ''
    try:
        if ext == '.docx':
            text = read_docx(path)
        elif ext == '.pdf':
            text = read_pdf(path)
        elif ext in ('.txt', '.md', '.log', '.csv', '.json'):
            text = read_text(path)
        elif ext == '.doc':
            text = ''
        else:
            text = ''
    except Exception as exc:
        print(json.dumps({'ok': False, 'name': name, 'ext': ext, 'text': '', 'error': str(exc)}, ensure_ascii=False))
        return
    print(json.dumps({'ok': True, 'name': name, 'ext': ext, 'text': text, 'chars': len(text)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
