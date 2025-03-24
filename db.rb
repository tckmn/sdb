$lvl = ['base', 'ms', 'plus', 'a1', 'a2', 'c1', 'c2', 'c3a', 'c3b', 'c4', 'all']

def to_type c
    case c
    when ?n then Number
    when ?r then Direction
    when ?d then Designator
    when ?f then Formation
    when ?c then :ENTRY
    when ?C then :BRACKET_ENTRY
    end
end

def entry? t; t == :ENTRY || t == :BRACKET_ENTRY; end
def concept? arr; arr.size == 2 && entry?(arr[-1]); end

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

class DbItem

    attr_accessor :lvl, :sd, :formal, :verbal, :specs, :timing
    class << self; attr_accessor :lookup; end
    def self.read_token token; self.lookup[token]; end

    def from_line line, register=false
        @lvl, *words = line.split
        abort "unknown level in #{line}" unless $lvl.include?(@lvl) || @lvl == 'ALIAS'
        @sd = to_sd words

        i = 0
        @formal = words.reject{|w| to_type(w) }.join.gsub(?-, '')
        @verbal = words.map{|w| to_type(w) ? "$#{i+=1}" : w }.join ' '

        @specs = {}
        @timing = 'untimed'

        if register
            self.class.lookup[@formal] = self
        end

        self
    end

    def self.head s
        self.lookup.each do |k,v|
            headlist, news = try_parse_head s, v.sd, true
            return [[v.formal]+headlist, news] if headlist
        end
        nil
    end

    def self.tail s
        self.lookup.each do |k,v|
            taillist, news = try_parse_tail s, v.sd, true
            return [[v.formal]+taillist, news] if taillist
        end
        return [nil, s]
    end

end

class Entry < DbItem; def self.head s; raise 'no'; end; def self.tail s; raise 'no'; end; end; Entry.lookup = {}
class Direction < DbItem; end; Direction.lookup = {}
class Formation < DbItem; end; Formation.lookup = {}
class Designator < DbItem; end; Designator.lookup = {}

class Number
    attr_accessor :sd, :val
    def self.read_token token; self.new.from_formal token; end

    def formal; self.val; end
    def verbal; self.val; end

    def from_formal formal; @val = formal; @sd = [formal]; self; end

    def self.head s
        a, b = s.split ' ', 2
        a.sub! /,$/, '' if a # TODO comma
        a =~ /^[0-9]+(\/[0-9]+)?$/ ? [[a], b || ''] : nil
    end

    def self.tail s
        [nil, s]
    end

    # TODO sometimes 1/4s and sometimes 1s oops. also this sucks lmao
    def timing; (4*self.val.to_r).to_i.to_s; end
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
        return self.head.verbal.gsub(/\$(\d+)/) { self.children[$1.to_i-1].verbal }.gsub(/\$-(\d+)/) { {
            'boys' => 'girls', 'girls' => 'boys',
            'heads' => 'sides', 'sides' => 'heads',
            'leads' => 'trailers', 'trailers' => 'leads', 'leaders' => 'trailers',
            'beaus' => 'belles', 'belles' => 'beaus',
            'centers' => 'ends', 'ends' => 'centers'
        }[self.children[$1.to_i-1].verbal] || 'others' }
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

def try_parse_head sd, slist, nocase = false
    [slist.flat_map do |token|
        case token
        when String
            return unless (nocase ? sd.downcase : sd).start_with? token
            sd = sd[token.size+1..-1] || ''
            sd = sd[1..-1] || '' if sd[0] == ' ' # TODO comma
            []
        else
            ret, sd = token.head sd
            return unless ret
            ret
        end
    end, sd]
end

def try_parse_tail sd, slist, nocase = false
    [slist.flat_map do |token|
        case token
        when String
            return unless (nocase ? sd.downcase : sd).end_with?(token)
            sd = sd[0...-(token.size+1)] || ''
            []
        else
            ret, sd = token.tail sd
            return unless ret
            ret
        end
    end, sd]
end

def try_parse sd, slist
    entrylocs = slist.each_index.select{|i| entry? slist[i] }
    if entrylocs.empty?
        ret, sd = try_parse_head sd, slist
        return unless ret
        return sd && sd.size > 0 ? nil : ret * ' '
    end

    # head
    headlist, sd = try_parse_head sd, slist[0...entrylocs[0]]
    return unless headlist

    # tail
    taillist, sd = try_parse_tail sd, slist[entrylocs[-1]+1..-1]
    return unless taillist

    # midpoint (oops it's getting dicey TODO)
    slist = slist[entrylocs[0]..entrylocs[-1]]
    midlist = []
    if slist.length == 3 && String === slist[1]
        parts = sd.split " #{slist[1]} "
        sd = nil
        return unless parts.size == 2
        ret = to_formal parts[0], slist[0]
        return unless ret
        midlist.push ret
        ret = to_formal parts[1], slist[2]
        return unless ret
        midlist.push ret
    elsif slist.length > 1
        raise "couldn't peel enough"
    elsif slist.length == 1
        ret = to_formal sd, slist[0]
        sd = nil
        return unless ret
        midlist.push ret
    end

    return (headlist+midlist+taillist).join ' ' unless sd && sd.size > 0
end

class Db
    attr_accessor :pbcache

    def initialize fname

        @cache = {}
        File.open('cache') do |f| @cache = Marshal.load f end rescue nil

        # TODO this really doesn't belong here
        @pbcache = {}
        File.open('pbcache') do |f| @pbcache = Marshal.load f end rescue nil

        @items = []   # real calls/designators/etc (excluding aliases and specs), used only for exposing lists to query
        entries = []  # for prefix/suffix/etc
        @taggers = Shortener.new

        cur = nil
        File.open(fname).each_line do |line|
            line.chomp!
            next if line.empty?
            next if line[0] == ?#
            cmd, args = line.split ' ', 2
            case cmd
            when 'ALIAS'
                src, dest = line.split ' = '
                cur = Entry.new.from_line src
                cur.formal = dest
                entries.push cur
            when 'MATCH'
                cur.sd = to_sd args.split
            when 'OUT'
                cur.verbal = args
            when 'TIME'
                cur.timing = args
            when 'TAGGER'
                @taggers.add cur.formal, args
            when 'SPEC'
                # TODO concatenating lvl and sd gives wrong results after MATCH
                # oh no this is now even more wrong help
                # god i have no idea what is happening here anymore i just won't touch it lmao
                k, v = args.split ' = '
                v ||= cur.lvl + ' ' + cur.sd.filter{|x|String===x}.join(' ')
                cur.specs[k] = Entry.new.from_line v
                a = Entry.new.from_line v
                a.formal = "#{cur.formal} #{k}"
                entries.push a
            else
                kls, data = line[0] == ?+ ? [to_type(line[1]), line[3..-1]] : [Entry, line]
                cur = kls.new.from_line data, true
                @items.push cur
                entries.push cur if kls == Entry
            end
        end

        # this is not used anywhere any more but it might be someday
        # and it's still useful to crosscheck for duplicates across types
        # jk it's used exactly once to expose levels in get_level
        @lookup = {}
        @items.each do |e|
            f = e.formal
            abort "duplicate key #{f}" if @lookup.include? f
            @lookup[f] = e
        end

        @nilads = {}
        @prefixes = Hash.new{|h,v| h[v] = []}
        @suffixes = Hash.new{|h,v| h[v] = []}
        @polyads = []
        entries.each do |e|
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

    def to_formal sd, t
        if t == :BRACKET_ENTRY
            return if sd[0] != ?[ || sd[-1] != ?]
            sd = sd[1..-2]
        end

        return @cache[sd] if @cache[sd]
        return @cache[sd] = @nilads[sd].formal if @nilads[sd]

        (@polyads + (@prefixes[sd.split[0]] || []) + (@suffixes[sd.split[-1]] || [])).each do |e|
            ret = try_parse sd, e.sd
            return @cache[sd] = "#{e.formal} #{ret}" if ret
        end

        # TODO special cases involving parentheses
        if sd[0] == ?(
            if sd[-1] == ?)
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
                    x = self.to_formal sd[1..idx-2], :ENTRY
                    y = self.to_formal sd[idx+2...-1], :ENTRY
                    return @cache[sd] = "seq #{x} #{y}" if x && y
                end
            elsif sd =~ /^\(.*\) ((\d+) TIMES|TWICE|1-(\d+)\/(\d+))$/
                frac = $2 || ($1 == 'TWICE' ? '2' : "#{$3.to_i+$4.to_i}/#$4")
                x = self.to_formal sd[1..-3-$1.size], :ENTRY
                return @cache[sd] = "do #{frac} #{x}" if x
            end
        end

        nil
    end

    # only called from to_tree
    def read_token type, tokens
        head = tokens.shift
        return nil unless head
        e = (entry?(type) ? Entry : type).read_token head
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
        self.read_token :ENTRY, formal.split
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
    def get_entries; @items; end
    def get_level formal; @lookup[formal] ? @lookup[formal].lvl : nil; end

    def save_cache
        File.open('cache', ?w) do |f| Marshal.dump $db.cache, f end if File.exists? 'cache'
        File.open('pbcache', ?w) do |f| Marshal.dump $db.pbcache, f end if File.exists? 'pbcache'
    end

end
