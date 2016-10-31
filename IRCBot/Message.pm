use warnings;
use strictures 2;

package IRCBot::Message;

# irc grammar {{{

=pod

from rfc1459

message    =  [ ":" prefix SPACE ] command [ params ] crlf
prefix     =  servername / ( nickname [ [ "!" user ] "@" host ] )
command    =  1*letter / 3digit
params     =  *14( SPACE middle ) [ SPACE ":" trailing ]
           =/ 14( SPACE middle ) [ SPACE [ ":" ] trailing ]

nospcrlfcl =  %x01-09 / %x0B-0C / %x0E-1F / %x21-39 / %x3B-FF
                ; any octet except NUL, CR, LF, " " and ":"
middle     =  nospcrlfcl *( ":" / nospcrlfcl )
trailing   =  *( ":" / " " / nospcrlfcl )

SPACE      =  %x20        ; space character
crlf       =  %x0D %x0A   ; "carriage return" "linefeed"

=cut

#}}}
sub new { #{{{
	my $class = shift;
	my $self = undef;

	if (1 == @_) {
		# message from string => parse
		$self = {};
		my $str = shift;
		bless $self, $class;
		$self->_inflate($str);
	}
	elsif (1 < @_) {
		# message from components => store components
		$self = {};
		my %components = @_;
		$self->{$_} = $components{$_} for keys %components;
		bless $self, $class;
	}
	return $self;
} #}}}
sub deflate { #{{{
	# does not/can not insert a prefix field, but this will
	# change if/when I see a client originating command that
	# uses it.
	my $self = shift;
	return undef unless exists $self->{command};
	for (@{$self->{params}}[0..$#{$self->{params}}-1]) {
		return ('error: nonlast param begins with colon ['.join(' ', caller).']', undef) if (substr($_, 0, 1) eq ':');
		return ('error: nonlast param contains space ['.join(' ', caller).']', undef) if / /;
	}
	my $output = '';
	if (defined $self->{prefix} && $self->{prefix} ne '') {
		$output = ":$self->{prefix} ";
	}
	$output .= (uc $self->{command});
	if (@{$self->{params}}) {
		$output .= ' '.join ' ', @{$self->{params}}[0..$#{$self->{params}}-1] if 1<@{$self->{params}};
		my $last = $self->{params}->[$#{$self->{params}}];
		if (substr($last, 0, 1) eq ':' or $last =~ / /) {
			$output .= " :$last";
		}
		else {
			$output .= " $last";
		}
	}
	return $output;
} #}}}
sub _inflate { #{{{
	# accepts stuff that would be nonvalid irc messages
	# but the important thing is that it parses what is
	# valid irc messages correctly
	my $self = $_[0];
	my $input = $_[1];
	{
		local $/ = "\r\n";
		chomp $input;
	}
	$input =~ /^(?::(?<prefix>\S+) )?(?<command>\S+)(?: (?<params>.*))?$/;
	my $params = $+{params};
	$self->{prefix} = $+{prefix};
	$self->{command} = uc $+{command};

	if (defined $self->{prefix}) { #{{{
		if ($self->{prefix} =~ /^(?<name>[^!@]+)(?:(?:!(?<user>[^@]+))?@(?<host>.*))?$/) {
			$self->{name} = $+{name};
			$self->{user} = $+{user};
			$self->{host} = $+{host};
		}
	} #}}}
	my @paramlist = ();
	while (defined($params) && $params ne '') { #{{{
		if (substr($params, 0, 1) eq ':') {
			push @paramlist, substr($params, 1);
			$params = '';
		}
		else {
			($paramlist[scalar @paramlist], $params) = split ' ', $params, 2;
		}
	} #}}}
	$self->{params} = \@paramlist;
	if ($self->{command} eq 'PRIVMSG' or $self->{command} eq 'NOTICE') {
		$self->{sanitized_message} = $self->{params}->[1];
		$self->{sanitized_message} =~ s/[\x00-\x02]|\x03\d{1,2}(?:,\d{1,2})?|[\x04-\x1f]//g;
		$self->{sanitized_message} =~ s/\x03//g;
	}
} #}}}
sub c { return $_[0]->{command}; }
sub ps { return @{$_[0]->{params}};}
sub nps { return $#{$_[0]->{params}};}
sub p0 { return $_[0]->{params}->[0]; }
sub p1 { return $_[0]->{params}->[1]; }
sub p2 { return $_[0]->{params}->[2]; }
sub p3 { return $_[0]->{params}->[3]; }

1;
