module Turbospec
  module Protocol
    READY = "READY"
    WORK = "WORK"
    NONE = "NONE"
    DONE = "DONE"

    def self.work_command(index)
      "#{WORK} #{index}"
    end

    def self.parse_work_command(response)
      match = response.match(/^#{WORK} (\d+)/)
      match ? match[1].to_i : nil
    end

    def self.result?(line)
      line.start_with?("{")
    end
  end
end
