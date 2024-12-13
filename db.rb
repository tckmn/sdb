$lvl = ['ms', 'plus', 'a1', 'a2', 'c1', 'c2', 'c3a', 'c3b', 'c4', 'all']

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
    attr_accessor :sd, :val

    # this is given formal input (see Db#read_token)
    def formal; self.val; end
    def verbal; self.val; end

    def self.fakenew val
        thing = self.new
        thing.val = val.downcase.gsub ' ', ''
        thing.sd = ['hi']
        thing
    end
    def self.from_formal formal; self.fakenew formal; end
    def self.from_sd x; x; end

    def self.head s
        case self::Domain
        when Array
            self::Domain.each do |t|
                return [self.fakenew(self.from_sd t), s[t.size+1..-1] || ''] if s.downcase.start_with? t
            end
        when Regexp
            if s =~ /(?i)^(#{self::Domain.source})($|,? )/
                return [self.fakenew(self.from_sd $1), $' || '']
            end
        end
        return [nil, s]
    end

    def self.tail s
        case self::Domain
        when Array
            self::Domain.each do |t|
                return [self.fakenew(self.from_sd t), s[0...-t.size-1]] if s.downcase.end_with? t
            end
        end
        return [nil, s]
    end

end

class Entry < Constituent

    attr_accessor :lvl, :sd, :formal, :verbal, :specs, :timing

    def self.fakenew val
        abort "called fakenew on Entry with #{val}"
    end

    def initialize line
        @lvl, *words = line.split
        abort "unknown level in #{line}" unless $lvl.include?(@lvl) || @lvl == 'ALIAS'
        @sd = to_sd words

        i = 0
        @formal = words.reject{|w| to_type(w) }.join.gsub(?-, '')
        @verbal = words.map{|w| to_type(w) ? "$#{i+=1}" : w }.join ' '

        @specs = {}
        @timing = 'untimed'
    end

end

class Number < Constituent
    def self.head s
        a, b = s.split ' ', 2
        a.sub! /,$/, '' if a # TODO a more unified way of doing this would be nice
        a =~ /^[0-9]+(\/[0-9]+)?$/ ? [self.fakenew(a), b || ''] : [nil, s]
    end
    def self.tail s
        [nil, s]
    end
    # TODO sometimes 1/4s and sometimes 1s oops. also this sucks lmao
    def timing; (4*self.val.to_r).to_i.to_s; end
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
    def timing
        # TODO add features gradually. also this sucks lmao
        t = self.head.timing
        return nil unless t
        bad = false
        t.gsub!(/\$(\d+)/) { tt = self.children[$1.to_i-1].timing; bad ||= !tt; tt }
        return nil if bad
        eval t
    end
end

class Shortener
    def initialize; @short2long = {}; @long2short = {}; end
    def add long, short; @long2short[long] = short; @short2long[short] = long; end
    def short long; @long2short[long]; end
    def long short; @short2long[short]; end
end

class Db

    def initialize fname

        @cache = {}
        File.open('cache') do |f| @cache = Marshal.load f end rescue nil

        @entries = [] # real calls (excluding aliases and specs), used to generate @lookup
        items = []    # everything
        @taggers = Shortener.new

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
                items.push cur
            when 'MATCH'
                cur.sd = to_sd args
            when 'OUT'
                cur.verbal = args.join ' '
            when 'TIME'
                cur.timing = args.join ' '
            when 'TAGGER'
                @taggers.add cur.formal, args.join(' ')
            when 'SPEC'
                # TODO concatenating lvl and sd gives wrong results after MATCH
                # oh no this is now even more wrong help
                k, v = args.join(' ').split ' = '
                v ||= cur.lvl + ' ' + cur.sd.filter{|x|String===x}.join(' ')
                cur.specs[k] = Entry.new v
                a = Entry.new v
                a.formal = "#{cur.formal} #{k}"
                items.push a
            else
                cur = Entry.new line
                @entries.push cur
                items.push cur
            end
        end

        @lookup = {}
        @entries.each do |e|
            f = e.formal
            abort "duplicate key #{f}" if @lookup.include? f
            @lookup[f] = e
        end

        @nilads = {}
        @prefixes = Hash.new{|h,v| h[v] = []}
        @suffixes = Hash.new{|h,v| h[v] = []}
        @polyads = []
        items.each do |e|
            if e.sd.size == 1
                @nilads[e.sd[0]] = e
            elsif String === e.sd[0]
                @prefixes[e.sd[0].split[0]].push e
            elsif String === e.sd[-1]
                @suffixes[e.sd[-1].split[-1]].push e
            else
                @polyads.push e
            end
        end

        # stupid hack lmao
        @prefixes.keys.each do |k|
            @prefixes[k+?,] = @prefixes[k]
        end

    end

    def try_parse sd, slist
        origsd = sd.dup
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
            raise "couldn't peel enough (#{[origsd, sd, slist].inspect})"
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

        if pref = @prefixes[sd.split[0]]
            pref.each do |e|
                ret = self.try_parse sd, e.sd
                return @cache[sd] = "#{e.formal} #{ret}" if ret
            end
        end

        if suff = @suffixes[sd.split[-1]]
            suff.each do |e|
                ret = self.try_parse sd, e.sd
                return @cache[sd] = "#{e.formal} #{ret}" if ret
            end
        end

        @polyads.each do |e|
            ret = self.try_parse sd, e.sd
            return @cache[sd] = "#{e.formal} #{ret}" if ret
        end

        # TODO special cases involving parentheses
        if sd =~ /^\(.*\) ((\d+) TIMES|TWICE|1-(\d+)\/(\d+))$/
            frac = $2 || ($1 == 'TWICE' ? '2' : "#{$3.to_i+$4.to_i}/#$4")
            x = self.to_formal sd[1..-3-$1.size]
            return @cache[sd] = "do #{frac} #{x}" if x
        end

        if sd[0] == ?( && sd[-1] == ?)
            dpth = 0
            depths = sd.chars.each.map do |ch,idx|
                case ch
                when ?(, ?[ then dpth += 1; dpth-1
                when ?), ?] then dpth -= 1; dpth
                else dpth
                end
            end
            idx = sd.gsub(/;/).map { $`.size }.find{|p| depths[p] == 1 }
            if idx
                x = self.to_formal sd[1..idx-2]
                y = self.to_formal sd[idx+2...-1]
                return @cache[sd] = "seq #{x} #{y}" if x && y
            end
        end

        if sd.end_with? ' (and adjust)'
            x = self.to_formal sd.sub(' (and adjust)', '')
            return @cache[sd] = x if x
        end

        nil
    end

    # only called from to_tree
    def read_token type, tokens
        head = tokens.shift
        return nil unless head
        e = @lookup[head] || type.from_formal(head)
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

    # only called from to_verbal and to_timing
    def to_tree formal
        return nil unless formal
        self.read_token Entry, formal.split
    end

    def to_verbal formal
        tree = self.to_tree formal
        return nil unless tree
        tree.verbal
    end

    def to_timing formal
        tree = self.to_tree formal
        return nil unless tree
        tree.timing
    end

    # TODO maybe better way to expose these (for query)
    def get_entries; @entries; end
    def get_level formal; @lookup[formal] ? @lookup[formal].lvl : nil; end

    def save_cache
        File.open('cache', ?w) do |f| Marshal.dump $db.cache, f end if File.exists? 'cache'
    end

end
