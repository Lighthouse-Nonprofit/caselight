# frozen_string_literal: true

# Builds tiny synthetic Casebook-shaped xlsx files for the Y5 importer specs —
# same anatomy as the real exports: a meta/title row, the header row, data rows,
# all on the LAST sheet. Minimal OOXML with inline strings (no sharedStrings /
# styles gymnastics); Roo::Excelx reads it fine.
module CasebookFixtureBuilder
  module_function

  def build_workbook(path, sheets)
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('[Content_Types].xml')
      zip.write content_types(sheets.size)
      zip.put_next_entry('_rels/.rels')
      zip.write root_rels
      zip.put_next_entry('xl/workbook.xml')
      zip.write workbook_xml(sheets.keys)
      zip.put_next_entry('xl/_rels/workbook.xml.rels')
      zip.write workbook_rels(sheets.size)
      zip.put_next_entry('xl/styles.xml')
      zip.write styles_xml
      sheets.values.each_with_index do |rows, i|
        zip.put_next_entry("xl/worksheets/sheet#{i + 1}.xml")
        zip.write sheet_xml(rows)
      end
    end
    path
  end

  # rows: array of arrays; title row + header + data supplied by the caller.
  def sheet_xml(rows)
    body = rows.each_with_index.map do |cells, r|
      cols = cells.each_with_index.map do |value, c|
        next '' if value.nil?
        ref = "#{column_letter(c)}#{r + 1}"
        "<c r=\"#{ref}\" t=\"inlineStr\"><is><t>#{escape(value)}</t></is></c>"
      end.join
      "<row r=\"#{r + 1}\">#{cols}</row>"
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{body}</sheetData></worksheet>
    XML
  end

  def column_letter(index)
    letters = ''
    i = index
    loop do
      letters = (65 + (i % 26)).chr + letters
      i = i / 26 - 1
      break if i.negative?
    end
    letters
  end

  def escape(value)
    value.to_s.encode(xml: :text)
  end

  def content_types(sheet_count)
    overrides = (1..sheet_count).map do |i|
      "<Override PartName=\"/xl/worksheets/sheet#{i}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        #{overrides}
      </Types>
    XML
  end

  def root_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      </Relationships>
    XML
  end

  def workbook_xml(names)
    sheets = names.each_with_index.map do |name, i|
      "<sheet name=\"#{escape(name)}\" sheetId=\"#{i + 1}\" r:id=\"rId#{i + 1}\"/>"
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{sheets}</sheets></workbook>
    XML
  end

  def workbook_rels(sheet_count)
    rels = (1..sheet_count).map do |i|
      "<Relationship Id=\"rId#{i}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet#{i}.xml\"/>"
    end.join
    styles = "<Relationship Id=\"rId#{sheet_count + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{rels}#{styles}</Relationships>
    XML
  end

  def styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
      </styleSheet>
    XML
  end
end
