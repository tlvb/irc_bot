use warnings;
use strictures 2;

package IRCBot::Event;

sub new { #{{{
	my $class = shift;
	my %setup = @_;
	my $self = \%setup;
	bless $self, $class;
} #}}}
sub deflate { #{{{
	my $self = shift;
	my $res = '{';
	$res .= sprintf '%s-->%s (%s)', $self->origin, $self->target, $self->type;
	for (grep {$_ !~ /origin|target|type/} sort keys %$self) {
		$res .= sprintf " %s='%s'", $_, $self->{$_} // '?';
	}
	$res .= '}';
	return $res;
} #}}}
sub type { return $_[0]->{type} // '-'; }
sub origin { return $_[0]->{origin} // '?'; }
sub target { return $_[0]->{target} // '*'; }

1;
