require 'stringio'

class BPlistParser
  def self.parse_file(fname)
    File.open(fname) do |fp|
      self.new(fp).top_object
    end
  end

  def initialize(io)
    @io = io
    read_header
    read_trailer
    @object_table = Hash.new do |h, k| 
      h[k] = read_object_table(k)
      h[k]
    end
  end

  def get_object(n)
    @object_table[n]
  end

  def top_object
    get_object(@top_object)
  end

  def read_header
    @io.seek(0, File::SEEK_SET)
    if @io.read(8) == 'bplist00'
      true
    else
      raise "file dose not start with 'bplist00' magic."
    end
  end

  def read_trailer
    @io.seek(-32, File::SEEK_END)
    ref_count_buf = @io.read(32)
    ary = ref_count_buf.unpack('x6CCx4Nx4Nx4N')
    offset_size, @ref_count, num_objects, @top_object, table_offset = ary
    @io.seek(table_offset, File::SEEK_SET)
    @offset_table = []
    num_objects.times do
      @offset_table << unpack_uint(@io.read(offset_size))
    end
  end

  def unpack_uint(buf)
    value = 0
    buf.each_byte {|x| value = value << 8 | x}
    value
  end

  def read_byte
    @io.read(1).unpack('C')[0]
  end

  def read_object_table(n)
    return nil unless @offset_table[n]
    @io.seek(@offset_table[n], File::SEEK_SET)
    marker = read_byte
    case (marker)
    when 0b0000_0000
      nil
    when 0b0000_1000
      false
    when 0b0000_1001
      true
    when 0b0000_1111
      nil #NOP
    when 0b0001_0001 .. 0b0001_1111
      read_int(1 << (marker & 0xf))
    when 0b0010_0001 .. 0b0010_1111
      read_real(1 << (marker & 0xf))
    when 0b0011_0011
      read_date
    when 0b0100_0000 .. 0b0100_1111
      count = read_count(marker & 0xf)
      read_data(count)
    when 0b0101_0000 .. 0b0101_1111
      count = read_count(marker & 0xf)
      read_ascii(count)
    when 0b0110_0000 .. 0b0110_1111
      count = read_count(marker & 0xf)
      read_unicode(count)
    when 0b1000_0000 .. 0b1000_1111
      read_uid(marker & 0xf)
    when 0b1010_0000 .. 0b1010_1111
      count = read_count(marker & 0xf)
      read_array(count)
    when 0b1101_0000 .. 0b1101_1111
      count = read_count(marker & 0xf)
      read_dict(count)
    else
      raise "illegal marker #{'%08b' % marker}"
    end
  end

  def read_count(count)
    return count if count < 0b1111
    marker = read_byte
    raise "illegal marker #{'%08b' % marker}" unless (marker & 0xf0) ==
      0b0001_0000
    read_int(1 << (marker & 0xf))
  end

  def read_int(count)
    raise "unsupported byte count: #{count}" if (count > 8)
    unpack_uint(@io.read(count))
  end

  def read_array(count)
    ary = read_ref(count)
    ary.collect {|x| get_object(x)}
  end

  def read_data(count)
    @io.read(count)
  end

  def read_ascii(count)
    @io.read(count)
  end

  def read_unicode(count)
    @io.read(count)
  end

  def read_uid(count)
    raise 'unsupported byte count' if count > 4
    @io.read(count)
  end

  def read_real(count)
    case count
    when 4
      @io.read(4).unpack('f')[0]
    when 8
      @io.read(8).unpack('d')[0]
    else
      raise 'unsupported byte count'
    end
  end

  def read_date
    read_real(8)
  end

  def read_ref(count)
    ary = []
    count.times do
      ary << unpack_uint(@io.read(@ref_count))
    end
    ary
  end

  def read_dict(count)
    keys = read_ref(count)
    refs = read_ref(count)
    hash = {}
    keys.zip(refs) do |k, v|
      hash[get_object(k)] = get_object(v)
    end
    hash
  end
end

if __FILE__ == $0
  web = BPlistParser.parse_file(ARGV.shift)
  p web.keys
  # body = web['WebMainResource']
  # p body['WebResourceMIMEType']
  # p body['WebResourceData'].force_encoding(body['WebResourceTextEncodingName'])
end

