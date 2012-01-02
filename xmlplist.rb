require 'date'
require 'base64'
require 'cgi/util'

module XMLPlist
  class Emitter
    def initialize
      @fiber = Fiber.new do |it|
        @plist = do_pop(it)
      end
    end
    attr_reader :plist
    
    def push(it)
      @fiber.resume(it)
    end
    
    def on_value(obj)
      push(obj)
    end
    
    def on_stag(name)
      push(name.intern)
    end

    def on_etag(name)
      push(('etag_' + name).intern)
    end

    def dict
      hash = Hash.new
      while key = pop_until(:etag_dict)
        hash[key] = pop
      end
      hash
    end

    def array
      ary = Array.new
      while elem = pop_until(:etag_array)
        ary.push(elem)
      end
      ary
    end
    
    def pop_until(symbol)
      it = pop
      return it unless Symbol === it
      return nil if it == symbol
      raise RuntimeError
    end
    
    def pop
      do_pop(Fiber.yield)
    end

    def do_pop(it)
      case it
      when :dict
        dict
      when :array
        array
      else
        it
      end
    end
  end

  module_function
  def from_file(fname)
    emitter = Emitter.new
    str = File.read(fname)
    str.scan(/<(key|string|data|date|real|integer)>(.*?)<\/\1>|<(true|false)\/>|<(array|dict)>|<\/(array|dict)>/m) do
      if $4
        emitter.on_stag($4)
      elsif $5
        emitter.on_etag($5)
      else
        value = if $1
                  case $1
                  when 'key', 'string'
                    ($2.include?('&')) ? CGI::unescapeHTML($2) : $2
                  when 'data'
                    Base64.decode64($2)
                  when 'date'
                    DateTime.parse($2)
                  when 'real'
                    $2.to_r
                  when 'integer'
                    $2.to_i
                  end
                elsif $3 == 'true'
                  true
                elsif $3 == 'false'
                  false
                else
                  raise RuntimeError
                end
        emitter.on_value(value)
      end
    end
    plist = emitter.plist
  end
end

if __FILE__ == $0
  it = XMLPlist.from_file(ARGV.shift)
  write_to = ARGV.shift
  if write_to
    File.open(write_to, 'w') {|fp| Marshal.dump(it, fp)}
  end
end
