use warnings;
use strict;
package IRC_Bot::Plugins::Log;

sub new { #{{{
	my $class = shift;
	my $self = {
		channels=>{}
	};
	bless $self, $class;
	return $self;
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
	return () unless $m->{command} eq 'PRIVMSG';
	my @ret = ();
	my $t = time;

	if (@c) {
		print '['.(join '][', @c)."]\n";
		# ( trg who comm params... )
		if (lc $c[2] eq 'help' and lc $c[3] eq 'log') {
			push @ret, ['PRIVMSG', $c[0], "$c[1]: .log grep STUFF -- search for stuff that people have said"];
		}
		if (lc $c[2] eq 'log') {
			if ($c[3] =~ /^grep (.*)/i) {
				my $words = $1;
				print "grepping for $words\n";
				$words =~ s/[^0-9A-Za-z _]+//g;
				my $re = qr/$words/;
				if (exists $self->{channels}->{$c[0]}) {
					my @loglines = ();
					for my $logline (@{$self->{channels}->{$c[0]}}) {
						my $l = $logline->[2];
						$l =~ s/[^0-9A-Za-z _]+//g;
						print "line $l\n";
						if ($l =~ /$re/) {
							print "match!\n";
							push @loglines, $logline;
							last if @loglines == 5;
						}
					}
					for my $logline (@loglines) {
						my $ts = $self->make_timestr($t-$logline->[0]);
						push @ret, ['PRIVMSG', $c[0], "$c[1]: [$ts: $logline->[1]: \"$logline->[2]\"]"];
					}
				}
			}
		}
	}
	if (not exists $self->{channels}->{$m->{params}->[0]}) {
		$self->{channels}->{$m->{params}->[0]} = [];
	}
	unshift @{$self->{channels}->{$m->{params}->[0]}}, [$t, $m->{name}, $m->{params}->[1]];
	pop @{$self->{channels}->{$m->{params}->[0]}} if @{$self->{channels}->{$m->{params}->[0]}} >= 10000;
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
