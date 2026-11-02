# -*- coding: utf-8 -*-
"""docx_export.py · 把口述整理稿导出为公文格式 DOCX

用法: python docx_export.py <payload.json> <output.docx>
payload.json:
{
  "title": "关于……的通知",
  "paragraphs": ["第一段……", "第二段……"],
  "signature": "单位/日期（可选）"
}

排版（参考 GB/T 9704 简化）:
  标题  方正小标宋简体 22pt 居中
  正文  仿宋_GB2312 16pt 首行缩进 2 字符 行距固定 28pt
  落款  仿宋_GB2312 16pt 右对齐
"""
import json
import sys

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.shared import Pt, Cm


def set_cn_font(run, name, size, bold=False):
    run.font.name = name
    run.font.size = Pt(size)
    run.font.bold = bold
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn('w:rFonts'))
    if rfonts is None:
        rfonts = rpr.makeelement(qn('w:rFonts'), {})
        rpr.append(rfonts)
    rfonts.set(qn('w:eastAsia'), name)


def add_para(doc, text, font, size, *, align=None, indent=False, bold=False, space_before=0, space_after=0):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    if indent:
        pf.first_line_indent = Pt(size * 2)
    pf.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    pf.line_spacing = Pt(28)
    run = p.add_run(text)
    set_cn_font(run, font, size, bold)
    return p


def main():
    payload_path = sys.argv[1]
    out_path = sys.argv[2]
    with open(payload_path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)

    title = (data.get('title') or '').strip()
    paragraphs = [p for p in (data.get('paragraphs') or []) if str(p).strip()]
    signature = (data.get('signature') or '').strip()

    doc = Document()
    sec = doc.sections[0]
    sec.top_margin = Cm(3.7)
    sec.bottom_margin = Cm(3.5)
    sec.left_margin = Cm(2.8)
    sec.right_margin = Cm(2.6)

    if title:
        add_para(doc, title, '方正小标宋简体', 22, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=12)

    for para in paragraphs:
        add_para(doc, str(para).strip(), '仿宋_GB2312', 16, indent=True)

    if signature:
        add_para(doc, signature, '仿宋_GB2312', 16, align=WD_ALIGN_PARAGRAPH.RIGHT, space_before=18)

    doc.save(out_path)


if __name__ == '__main__':
    main()
