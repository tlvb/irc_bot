use strict;
use warnings;
package IRC_Bot::IRC_IO;
use IO::Socket::INET;
use IO::Socket::SSL;
use IO::Select;


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


sub new { #{{{
	my $class = shift;
	my %opts = (ssl=>0, log=>'/tmp/irc_raw_log', ssl_opts=>{}, inet_opts=>{}, @_);
	my $self = {opts=>\%opts, plugins=>{}, listeners=>{}, socket=>undef, logfd=>undef};
	open $self->{logfd}, '>>', $opts{log} or die "no irc without a log:\n$!";
	bless $self, $class;
	return $self;
} #}}}
sub connect { #{{{
	my $self = shift;
	my $host = shift // $self->{host};
	my $port = shift // $self->{port};

	print STDERR "attempting to connect to host '$host', on port '$port'\n";
	$self->{host} = $host;
	$self->{port} = $port;
	if ($self->{opts}->{ssl} != 0) { #{{{
		$self->{socket} = IO::Socket::SSL->new(
			PeerHost => $host,
			PeerPort => $port,
			%{$self->{opts}->{ssl_opts}}
		);
	} #}}}
	else { #{{{
		$self->{socket} = IO::Socket::INET->new(
			PeerHost => $host,
			PeerPort => $port,
			%{$self->{opts}->{inet_opts}}
		);
	} #}}}
	return -1 unless defined $self->{socket};
	if ($self->{socket}->connected()) {
		$self->{select} = IO::Select->new($self->{socket});
		return 0;
	}
	return -1;
} #}}}
sub close { #{{{
	my $self = shift;
	CORE::close close $self->{socket} if defined $self->{socket};
	close $self->{fd};
} #}}}
sub is_connected { #{{{
	my $self = shift;
	return 0 unless defined $self->{socket};
	return 1 if defined $self->{socket}->connected();
	return 0;
} #}}}
sub reconnect { #{{{
	my $self = shift;
	my $socket = $self->{socket};
	CORE::close $socket;
	$self->connect();
} #}}}
sub _parse { #{{{
	# accepts stuff that would be nonvalid irc messages
	# but the important thing is that it parses what is
	# valid irc messages correctly
	my $input = $_[0];
	{
		local $/ = "\r\n";
		chomp $input;
	}
	my %parsed = ();
	$input =~ /^(?::(?<prefix>\S+) )?(?<command>\S+)(?: (?<params>.*))?$/;
	my $params = $+{params};
	$parsed{prefix} = $+{prefix};
	$parsed{command} = uc $+{command};

	if (defined $parsed{prefix}) { #{{{
		if ($parsed{prefix} =~ /^(?<name>[^!@]+)(?:(?:!(?<user>[^@]+))?@(?<host>.*))?$/) {
			$parsed{name} = $+{name};
			$parsed{user} = $+{user};
			$parsed{host} = $+{host};
		}
	} #}}}
	my @paramlist = ();
	while (defined($params) and $params ne '') { #{{{
		if (substr($params, 0, 1) eq ':') {
			push @paramlist, substr($params, 1);
			$params = '';
		}
		else {
			($paramlist[scalar @paramlist], $params) = split /\s+/, $params, 2;
		}
	} #}}}
	$parsed{params} = \@paramlist;
	if ($parsed{command} eq 'PRIVMSG' or $parsed{command} eq 'NOTICE') {
		$parsed{sanitized_message} = $parsed{params}->[1];
		$parsed{sanitized_message} =~ s/[\x00-\x02]|\x03\d{1,2}(?:,\d{1,2})?|[\x04-\x1f]//g;
		$parsed{sanitized_message} =~ s/\x03//g;

	}

	return \%parsed;
} #}}}
sub _unparse { #{{{
	# does not/can not insert a prefix field, but this will
	# change if/when I see a client originating command that
	# uses it.
	my %input = %{$_[0]};
	die 'error: no command ['.join(' ', caller).']' unless exists $input{command};
	for (@{$input{params}}[0..$#{$input{params}}-1]) {
		die 'error: nonlast param begins with colon ['.join(' ', caller).']' if (substr($_, 0, 1) eq ':');
		die 'error: nonlast param contains space ['.join(' ', caller).']' if / /;
	}
	my $output = '';
	$output = (uc $input{command});
	if (@{$input{params}}) {
		if (@{$input{params}} > 1) {
			$output .= ' '.join ' ', @{$input{params}}[0..$#{$input{params}}-1];
		}
		my $last = $input{params}->[$#{$input{params}}];
		if (substr($last, 0, 1) eq ':' or $last =~ / /) {
			$output .= " :$last";
		}
		else {
			$output .= " $last";
		}
	}
	return $output."\r\n";
} #}}}
sub _ppp { #{{{
	my $bold = "\x1b[1m";
	my $reset = "\x1b[0m";
	my $m = shift;
	my $redact = (shift @_) // 0;
	if (defined $m->{prefix}) {
		print ":$bold$m->{name}$reset";
		if (defined $m->{host}) {
			if (defined $m->{user}){
				print "!$m->{user}";
			}
			print "\@$m->{host}";
		}
		print " ";
	}
	print "$bold$m->{command}$reset";
	if ($redact) {
		print " [parameter list redacted]";
	}
	elsif (defined $m->{params}) {
		for (0..$#{$m->{params}}-1) {
			print " $m->{params}->[$_]";
		}
		my $last = $m->{params}->[$#{$m->{params}}];
		if (substr($last, 0, 1) eq ':' or $last =~ / /) {
			print " :$last";
		}
		else {
			print " $last";
		}
	}
} #}}}
sub receive { #{{{
	# returns a hash of the fields of the received irc message
	# prefix (whole prefix)
	# name
	# user
	# host
	# command
	# params (list ref of all parameters, leading colon removed from
	#        the last parameter if present)

	my $self = shift;
	my $timeout = $_[0] // 0;
	my @socks = $self->{select}->can_read($timeout);
	if (@socks == 0) {
		print "--- INPUT WAIT TIMEOUT REACHED\n";
		return {ERROR=>'TIMEOUT'};
	}
	my $socket = $self->{socket};
	my $line = '';
	{
		local $/ = "\r\n";
		while ($line =~ /^\s*$/) {
			$line = <$socket>;
			if (not defined $line) {
				if ($socket->connected()) {
					print "--- UNDEFINED INPUT, SOCKET IS STILL CONNECTED\n";
					return {ERROR=>'UNDEFINED'};
				}
				else {
					print "--- UNDEFINED INPUT, SOCKET IS CLOSED\n";
					return {ERROR=>'CLOSED'};
				}
			}
		}
		print {$self->{logfd}} time.'[>]: '.$line;
		chomp $line;
	}
	my $msg = _parse($line);
	print ">>> ";
	_ppp $msg;
	print "\n";
	return $msg;
} #}}}
sub send { #{{{
	# sends, and logs to stdout, a message hash
	# of the same kind that is returned by receive
	my $self = shift;
	my $socket = $self->{socket};
	my $msg = shift;
	print "<<< ";
	_ppp $msg, $self->{redact};
	print "\n";
	my $raw = _unparse($msg);
	print {$self->{logfd}} time.'[<]: '.$raw;
	print $socket _unparse($msg);
	flush $socket;
	return $self;
} #}}}
sub csend { #{{{
	# standard function to send any command constructed
	# from the list of parameters
	my $self = shift;
	my $socket = $self->{socket};
	my $command = shift;
	my @params = @_;
	my $msg = {command=>$command, params=>\@params};
	print "<<< ";
	_ppp $msg, $self->{redact};
	print "\n";
	my $raw = _unparse($msg);
	print {$self->{logfd}} time.'[<]: '.$raw;
	print $socket $raw;
	flush $socket;
	return $self;
} #}}}
sub msg { #{{{
	# standard privmsg helper function
	# $ircio->msg('target', 'the message') builds and sends
	# the irc command <PRIVMSG target :the message>
	# $ircio->msg('target', 'alice', 'bob', 'a secret') builds
	# and sends the command <PRIVMSG target :alice, bob: a secret>
	my $self = shift;
	my $target = shift;
	my $message = pop;
	my $audience = @_?join(', ',@_).': ':'';
	$self->csend('PRIVMSG', $target, $audience.$message);
	return $self;
} #}}}
sub redact { #{{{
	# when redact(1) is active, PARAMETERS of sent commands
	# will be obfuscated on stdout, in order to stop e.g.
	# the password sent during sasl or NickServ auth from
	# being logged. efective until redact(0)
	my $self = shift;
	$self->{redact} = shift;
	return $self;
} #}}}

1;

