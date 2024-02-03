def to_type c
    case c
    when ?n then Number
    when ?r then Direction
    when ?d then Designator
    when ?f, "f'" then Formation
    when ?c then Entry
    end
end

def concept? arr
    arr.size == 2 && arr[-1] == Entry
end

# WARNING: mutates words
def to_sd words
    lower = words[-1] == 'LOWER'
    upper = words[-1] == 'UPPER'
    words.pop if lower || upper

    ret = words.slice_when{|w,v| to_type(w) || to_type(v)}.map{|x|
        to_type(x[0]) || x.join(' ').gsub(?&, 'and')
    }
    ret.map!{|x| x.is_a?(String) ? x.upcase : x} if upper || (concept?(ret) && !lower)

    ret
end

class Constituent
    attr_accessor :val

    # this is given formal input (see Db#read_token)
    def initialize val; @val = val.downcase.gsub ' ', ''; end
    def formal; self.val; end
    def verbal; self.val; end

    def self.from_sd x; x; end

    def self.head s
        case self::Domain
        when Array
            self::Domain.each do |t|
                return [self.new(self.from_sd t), s[t.size+1..-1] || ''] if s.downcase.start_with? t
            end
        when Regexp
            if s =~ /(?i)^(#{self::Domain.source})($|,? )/
                return [self.new(self.from_sd $1), $' || '']
            end
        end
        return [nil, s]
    end

    def self.tail s
        case self::Domain
        when Array
            self::Domain.each do |t|
                return [self.new(self.from_sd t), s[0...-t.size-1]] if s.downcase.end_with? t
            end
        end
        return [nil, s]
    end

end

class Entry < Constituent

    attr_accessor :lvl, :sd, :formal, :verbal, :specs

    def initialize line
        @lvl, *words = line.split
        @sd = to_sd words

        i = 0
        @formal = words.reject{|w| to_type(w) }.join.gsub(?-, '')
        @verbal = words.map{|w| to_type(w) ? "$#{i+=1}" : w }.join ' '

        @specs = {}
    end

end

class Number < Constituent
    def self.head s
        a, b = s.split ' ', 2
        a.sub! /,$/, '' if a # TODO a more unified way of doing this would be nice
        a =~ /^[0-9]+(\/[0-9]+)?$/ ? [self.new(a), b] : [nil, s]
    end
    def self.tail s
        [nil, s]
    end
end

class Direction < Constituent
    Domain = 'right|left|in|out|forward|backward'.split ?|
end

class Designator < Constituent
    Domain = /heads|sides|(head |side |)(boys|girls)|lead(er)?s|trailers|beaus|belles|(leading |trailing |very |)(centers|ends)|center \d|#\d couple|near \d|far \d|those facing/
    def self.from_sd x; x == 'leaders' ? 'leads' : x; end
    def verbal; self.val.sub /(very|head|side|ing|center|#\d|near|far|those)(?!s)/, '\0 '; end
end

class Formation < Constituent
    Domain = 'lines|waves|columns|diamonds|boxes'.split ?|
end

class Node
    attr_accessor :head, :children
    def initialize head, children=[]
        @head = head
        @children = children
    end
    def verbal
        # TODO this sucks lmao
        if self.children.size > 0
            arr = self.children.map{|c| c.head.formal}
            (1..self.children.size).each do |i|
                arr = self.children.map{|c| c.head.formal}
                s = self.head.specs[arr[0...i].join ' ']
                return s.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1+i].verbal } if s
            end
        end
        return self.head.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1].verbal }
    end
end

class Db

    attr_accessor :entries, :aliases, :lookup, :nilads, :polyads, :cache

    def initialize fname

        @cache = {}
        File.open('cache') do |f| @cache = Marshal.load f end rescue nil

        @entries = []
        @aliases = []
        cur = nil
        File.open(fname).each_line do |line|
            line.chomp!
            next if line.empty?
            next if line[0] == ?#
            cmd, *args = line.split
            case cmd
            when 'ALIAS'
                src, dest = line.split ' = '
                cur = Entry.new src
                cur.formal = dest
                @aliases.push cur
            when 'MATCH'
                cur.sd = to_sd args
            when 'OUT'
                cur.verbal = args.join ' '
            when 'SPEC'
                # TODO concatenating lvl and sd gives wrong results after MATCH
                # oh no this is now even more wrong help
                k, v = args.join(' ').split ' = '
                v ||= cur.lvl + ' ' + cur.sd.filter{|x|String===x}.join(' ')
                cur.specs[k] = Entry.new v
                a = Entry.new v
                a.formal = "#{cur.formal} #{k}"
                @aliases.push a
            else
                cur = Entry.new line
                @entries.push cur
            end
        end

        @lookup = {}
        @entries.each do |e|
            @lookup[e.formal] = e
        end

        @nilads = {}
        @polyads = []
        (@entries+@aliases).each do |e|
            if e.sd.size == 1
                @nilads[e.sd[0]] = e
            else
                @polyads.push e
            end
        end

    end

    def parse_arg type, sd
        return self.to_formal sd if type == ?c
        arg, s = to_type(type).head sd
        !s || s == '' ? arg.formal : nil
    end

    def try_parse sd, slist
        slist = slist.dup
        headlist = []
        midlist = []
        taillist = []

        # head
        until slist.empty? || slist[0] == Entry
            token = slist.shift
            case token
            when String
                return unless sd.start_with?(token)
                sd = sd[token.size+1..-1] || ''
                # TODO hacks
                sd = sd[1..-1] || '' if sd[0] == ' ' # for commas
                sd = sd[1..-2] || '' if sd[0] == '[' && sd[-1] == ']' # for brackets
            else
                ret, sd = token.head sd
                return unless ret
                headlist.push ret.formal
            end
        end

        # tail
        until slist.empty? || slist[-1] == Entry
            token = slist.pop
            case token
            when String
                return unless sd.end_with?(token)
                sd = sd[0...-(token.size+1)] || ''
                sd = sd[1..-2] || '' if sd[0] == '[' && sd[-1] == ']' # for brackets
            else
                ret, sd = token.tail sd
                return unless ret
                taillist.push ret.formal
            end
        end

        # midpoint (oops it's getting dicey TODO)
        if slist.length == 3 && String === slist[1]
            abort 'what' if slist[0] != Entry || slist[2] != Entry
            parts = sd.split " #{slist[1]} "
            sd = nil
            return unless parts.size == 2
            ret = to_formal parts[0]
            return unless ret
            midlist.push ret
            ret = to_formal parts[1]
            return unless ret
            midlist.push ret
        elsif slist.length > 1
            raise "couldn't peel enough"
        elsif slist.length == 1
            ret = to_formal sd
            sd = nil
            return unless ret
            midlist.push ret
        end

        return (headlist+midlist+taillist).join ' ' unless sd && sd.size > 0
    end

    def to_formal sd
        return @cache[sd] if @cache[sd]

        if @nilads[sd]
            return @cache[sd] = @nilads[sd].formal
        end

        @polyads.each do |e|
            ret = self.try_parse sd, e.sd
            return @cache[sd] = "#{e.formal} #{ret}" if ret
        end

        # TODO special case
        if sd =~ /^\(.*\) (\d+) TIMES$/
            frac = $1
            x = self.parse_arg ?c, sd[1..-9-frac.size]
            return @cache[sd] = "do #{frac} #{x}" if x
        end

        if sd.end_with? '(and adjust)'
            x = self.to_formal sd.sub(' (and adjust)', '')
            return @cache[sd] = x if x
        end

        nil
    end

    def read_token type, tokens
        head = tokens.shift
        if type == Entry
            e = @lookup[head]
            return nil unless e
            args = []
            e.sd.each do |a|
                unless String === a
                    t = self.read_token a, tokens
                    return nil unless t
                    args.push t
                end
            end
            return Node.new e, args
        end
        return Node.new(type.new head)
    end

    def to_verbal formal
        return nil unless formal
        tree = self.read_token Entry, formal.split
        return nil unless tree
        tree.verbal
    end

end
