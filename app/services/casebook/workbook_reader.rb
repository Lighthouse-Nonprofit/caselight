# frozen_string_literal: true

module Casebook
  # Reads one Casebook dashboard export (xlsx). The raw export table is the LAST
  # sheet of every workbook: a title/meta row or two (<= META_MAX_CELLS non-blank
  # cells), then the header row, then data. Yields one {header => value} hash per
  # data row — strings stripped, dates left as Date (Roo parses date cells).
  class WorkbookReader
    META_MAX_CELLS = 3

    attr_reader :path

    def initialize(path)
      @path = path.to_s
    end

    def headers
      @headers ||= begin
        each_row { break } if @headers.nil? # locate the header row lazily
        @headers || []
      end
    end

    def each_row
      sheet = workbook.sheet(workbook.sheets.last)
      @headers = nil
      (sheet.first_row..sheet.last_row).each do |i|
        row = sheet.row(i)
        non_blank = row.count { |v| !v.to_s.strip.empty? }
        if @headers.nil?
          @headers = row.map { |v| v.to_s.strip } if non_blank > META_MAX_CELLS
          next
        end
        next if non_blank.zero?
        yield @headers.zip(row.map { |v| v.is_a?(String) ? v.strip : v }).to_h
      end
    end

    def rows
      out = []
      each_row { |r| out << r }
      out
    end

    private

    def workbook
      @workbook ||= Roo::Excelx.new(path)
    end
  end
end
