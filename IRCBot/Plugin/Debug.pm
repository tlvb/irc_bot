use warnings;
use strictures 2;
package IRCBot::Plugin::Debug;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::ConfigReader;
use IRCBot::Message;
use MIME::Base64;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} =
	            ('0.1.0',);
	bless $self, $class;
	return $self;
} #}}}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	if ($e->type eq 'ACL-RESPONSE') {
		my $p = $e->{data};
		my $t = $p->{respond_prefix};
		my $enick = $e->{nick};
		my $acl = $e->{acl_data};
		if (defined $acl) {
			my $chandata = undef;
			$t .= "Nick: $enick.";
			if (exists $acl->{login}) {
				$t .= " NickServ account = '$acl->{login}'.";
			}
			else {
				$t .= ' Nickserv account = Not Authenticated.';
			}
			if (defined $acl->{channel}->{$p->{respond_target}}) {
				$t .= ' Local flags: '.((join ',', @{$acl->{channel}->{$p->{respond_target}}}) || 'none').'.';
			}
			$t .= ' Trust level: '.$acl->{trust}.'.';
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[
					$p->{respond_target},
					$t]);
		}
		else {
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[
					$p->{respond_target},
					"No such nick exists: '$enick'."]);
		}
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;

	if ($m->c eq 'PRIVMSG') {
		my $p = $self->decode_privmsg($m);
		my $s = 'privmsg: ';
		for (sort keys %$p) {
			$s .= " $_=>'$p->{$_}'";
		}
		$self->log_d($s);
		if ($p->{addressed}) {
			my ($directive,$rest) = split /\s+/, $p->{message}, 3;
			if ($directive eq 'acl-check') {
				$self->emit_event(target=>'acl', origin=>'debug', type=>'ACL-QUERY', nick=>$rest, data=>$p);
			}
		}
	}
} #}}}
1;

