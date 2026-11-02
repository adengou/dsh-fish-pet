# -*- coding: utf-8 -*-
"""briefing_docx.py · 把每日工作简报写成 DOCX（机关简报排版）

用法: python briefing_docx.py <payload.json> <output.docx>
payload.json 结构:
{
  "date": "2026-11-02",
  "sessions": ["会话标题1", "会话标题2"],
  "weather": "今天...",
  "notes": ["待办1", "待办2"],
  "speech": "鱼播报的那句话（可选）"
}

排版约定（参考机关公文习惯）:
  标题  方正小标宋简体 22pt 居中
  日期  仿宋_GB2312 14pt 居中
  小标题 黑体 16pt
  正文  仿宋_GB2312 16pt 首行缩进 2 字符 行距固定 28pt
"""
import json
import sys
from datetime import datetime

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

    date_str = data.get('date') or datetime.now().strftime('%Y-%m-%d')
    try:
        dt = datetime.strptime(date_str, '%Y-%m-%d')
        date_cn = '{}年{}月{}日'.format(dt.year, dt.month, dt.day)
    except Exception:
        date_cn = date_str

    sessions = [s for s in (data.get('sessions') or []) if s]
    weather = (data.get('weather') or '').strip()
    notes = [n for n in (data.get('notes') or []) if n]
    speech = (data.get('speech') or '').strip()

    doc = Document()
    sec = doc.sections[0]
    sec.top_margin = Cm(3.7)
    sec.bottom_margin = Cm(3.5)
    sec.left_margin = Cm(2.8)
    sec.right_margin = Cm(2.6)

    # 标题
    add_para(doc, '工作简报', '方正小标宋简体', 22, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=6)
    # 日期
    add_para(doc, date_cn, '仿宋_GB2312', 14, align=WD_ALIGN_PARAGRAPH.CENTER, space_after=18)
    # 分隔线
    p = doc.add_paragraph()
    pPr = p._element.get_or_add_pPr()
    from docx.oxml import OxmlElement
    pbdr = OxmlElement('w:pBdr')
    bottom = OxmlElement('w:bottom')
    bottom.set(qn('w:val'), 'single')
    bottom.set(qn('w:sz'), '8')
    bottom.set(qn('w:space'), '1')
    bottom.set(qn('w:color'), '000000')
    pbdr.append(bottom)
    pPr.append(pbdr)

    # 一、今日工作
    add_para(doc, '一、今日工作', '黑体', 16, space_before=8, space_after=4)
    if sessions:
        for i, title in enumerate(sessions, 1):
            add_para(doc, '（{}）{}'.format(i, title), '仿宋_GB2312', 16)
    else:
        add_para(doc, '今日 DSH 暂无新的工作会话。', '仿宋_GB2312', 16)

    # 二、天气
    add_para(doc, '二、天气情况', '黑体', 16, space_before=8, space_after=4)
    add_para(doc, weather if weather else '暂无天气数据。', '仿宋_GB2312', 16)

    # 三、待办提醒
    add_para(doc, '三、待办提醒', '黑体', 16, space_before=8, space_after=4)
    if notes:
        for i, n in enumerate(notes, 1):
            add_para(doc, '（{}）{}'.format(i, n), '仿宋_GB2312', 16)
    else:
        add_para(doc, '今日无待办提醒。', '仿宋_GB2312', 16)

    # 附：鱼的原话
    if speech:
        add_para(doc, '附：鱼的原话', '楷体_GB2312', 14, space_before=16, space_after=4)
        add_para(doc, speech, '楷体_GB2312', 14)

    doc.save(out_path)


if __name__ == '__main__':
    main()
