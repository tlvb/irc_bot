use strict;
use warnings;
no warnings 'redefine';

package IRC_Bot::Plugins::Seen;
use POSIX;

sub new { #{{{
	my $class = shift;
	my $self = {
		channels=>{},
		hookid=>0,
		hooks=>{}
	};
	bless $self, $class;
	return $self;
} #}}}
sub add_morehook { #{{{
	my $self = $_[0];
	my $owner = $_[1];
	my $content = $_[2];
	if (exists $self->{hooks}->{$owner}) {
		if ($self->{hooks}->{$owner}->{id} != $self->{hookid}) {
			$self->{hooks}->{$owner} = {id=>$self->{hookid},content=>[]};
			push @{$self->{hooks}->{$owner}->{content}}, $content;
		}
	}
	else {
		$self->{hooks}->{$owner} = {id=>$self->{hookid},content=>[$content]};
	}
} #}}}
sub retrieve_morehook { #{{{
	my $self = $_[0];
	my $owner = $_[1];
	my @returns = ();
	if (exists $self->{hooks}->{$owner}) {
		for (@{$self->{hooks}->{$owner}->{content}}) {
			push @returns, $_;
		}
		delete $self->{hooks}->{$owner};
	}
	return @returns;
} #}}}
sub ensure_channel_existence { #{{{
	my $self = $_[0];
	my $channel = $_[1];
	$self->{channels}->{$channel} = {} unless exists $self->{channels}->{$channel};
	return $channel;
} #}}}
sub ensure_nick_existence { #{{{
	my $self = $_[0];
	my $channel = $_[1];
	my $nick = $_[2];
	$self->{channels}->{$channel}->{$nick} = {} unless exists $self->{channels}->{$channel}->{$nick};
	return $nick;
} #}}}
sub make_excerpt { #{{{
	my $self = $_[0];
	my $msg = $_[1];
	if (length($msg) <= 32) {
		return ($msg, undef);
	}
	else {
		return (substr($msg, 0, 32), $msg);
	}
} #}}}
sub set_lastaction { #{{{
	$_[0]->{channels}->{$_[1]}->{$_[2]}->{lastaction} = $_[3];
} #}}}
sub set_lastmessage { #{{{
	$_[0]->{channels}->{$_[1]}->{$_[2]}->{lastmessage} = $_[3];
} #}}}
sub make_timestr { #{{{
	my $self = $_[0];
	my $dt = $_[1];
	my $s = $dt % 60; $dt -= $s; $dt /= 60;
	my $m = $dt % 60; $dt -= $m; $dt /= 60;
	my $h = $dt % 24; $dt -= $h; $dt /= 24;
	my $d = $dt;
	my $tstr = '';
	$tstr .= "${d}d " if ($d > 0);
	$tstr .= "${h}h " if ($h > 0);
	$tstr .= "${m}m " if ($m > 0);
	$tstr .= "${s}s " if ($s > 0);
	$tstr .= 'ago';
	return $tstr;
} #}}}
sub handle_input { #{{{
	my $self = shift;
	my $m = shift;
	my $mynick = shift;
	my @c = @_;

	my @ret = ();
	my $t = time;

	if (@c) { #{{{
		# a command
		# ( trg who comm params... )
		if ($c[2] eq 'seen') {
			if ($c[3] eq '...') {
				push @ret, ['PRIVMSG', $c[0], "$c[1]: $_"] for $self->retrieve_morehook($c[1]);
			}
			elsif (exists $self->{channels}->{$c[0]}->{$c[3]}) {
				my %info = %{$self->{channels}->{$c[0]}->{$c[3]}};
				my @reply = ($c[3]);
				if (exists $info{lastmessage}) {
					my ($lmt, $lm) = @{$info{lastmessage}};
					my $dts = $self->make_timestr($t - $lmt);
					my ($lme, $lml) = $self->make_excerpt($lm);
					if (defined $lml) {
						$self->add_morehook($c[1], "[ $c[3] ]  [ MSG: \"$lml\" ]");
						push @reply, "MSG: \"$lme...\" (truncated)\" $dts";
					}
					else {
						push @reply, "MSG: \"$lme\" $dts";
					}
				}
				if (exists $info{lastaction}) {
					my ($lat, $la, $extra) = @{$info{lastaction}};
					my $dts = $self->make_timestr($t - $lat);
					if (defined $extra) {
						$self->add_morehook($c[1], "[ $c[3] ]  [ ACT: \"$extra\" ]");
						push @reply, "ACT: $la ... (truncated) $dts";
					}
					else {
						push @reply, "ACT: $la $dts";
					}
				}
				push @ret, ['PRIVMSG', $c[0], "$c[1]: [ ".(join ' ]  [ ', @reply).' ]'];
			}
			else {
				push @ret, ['PRIVMSG', $c[0], "$c[1]: no info on $c[3]"];
			}
		}
		elsif ($c[2] eq 'help' and $c[3] eq 'seen') {
			push @ret, ['PRIVMSG', $c[0], "$c[1]: .seen NICK -- for info about their last known action, .seen ... to reveal truncated parts of messages"];
		}
	} #}}}
	else { #{{{
		if ($m->{command} eq 'JOIN') { #{{{
			my $channel = $self->ensure_channel_existence($m->{params}->[0]);
			my $nick = $m->{name};
			$self->ensure_nick_existence($channel, $nick);
			$self->set_lastaction($channel, $nick, [$t, 'join']);
		} #}}}
		elsif ($m->{command} eq 'PART') { #{{{
			my $channel = $self->ensure_channel_existence($m->{params}->[0]);
			my $nick = $m->{name};
			$self->ensure_nick_existence($channel, $nick);
			$self->set_lastaction($channel, $nick, [$t, 'part', $m->{params}->[2]]);
		} #}}}
		elsif ($m->{command} eq 'QUIT') { #{{{
			my $nick = $m->{name};
			for (keys %{$self->{channels}}) {
				$self->ensure_nick_existence($_, $nick);
				$self->set_lastaction($_, $nick, [$t, 'quit', $m->{params}->[1]]);
			}
		} #}}}
		elsif ($m->{command} eq 'NICK') { #{{{
			my $from_nick = $m->{name};
			my $to_nick = $m->{params}->[0];
			for (keys %{$self->{channels}}) {
				$self->ensure_nick_existence($_, $from_nick);
				$self->set_lastaction($_, $from_nick, [$t, "nick (to) $to_nick"]);
				$self->ensure_nick_existence($_, $to_nick);
				$self->set_lastaction($_, $to_nick, [$t, "nick (from) $from_nick"]);
			}
		} #}}}
		elsif ($m->{command} eq 'KICK') { #{{{
			my $by_nick = $m->{name};
			my $channel = $m->{params}->[0];
			my $who_nick = $m->{params}->[1];
			$self->ensure_nick_existence($channel, $by_nick);
			$self->set_lastaction($channel, $by_nick, [$t, "kicked $who_nick", $m->{params}->[2]]);
			$self->ensure_nick_existence($channel, $who_nick);
			$self->set_lastaction($channel, $who_nick, [$t, "kicked (by) $by_nick", $m->{params}->[2]]);
		} #}}}
		elsif ($m->{command} eq 'PRIVMSG') {
			my $nick = $m->{name};
			my $channel = $self->ensure_channel_existence($m->{params}->[0]);
			$self->ensure_nick_existence($channel, $nick);
			$self->set_lastmessage($channel, $nick, [$t, $m->{params}->[1]]);
		}
	} #}}}
	$self->{hookid} += 1;
	return @ret;
} #}}}
sub load { #{{{
	my ($self, $data) = @_;
	$self->{channels} = $data;
} #}}}
sub save { #{{{
	my $self = $_[0];
	my $data = $self->{channels};
	return $data;
} #}}}

1;
