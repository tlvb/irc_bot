use warnings;
use strict;
package IRC_Bot::Plugins::DumpRaw;

sub new { #{{{
	my $class = shift;
	my $self = {
		protected=>1,
		logs=>[]
	};
	bless $self, $class;
	return $self;
} #}}}

sub handle_input { #{{{
	my $self = shift;
	my $m = shift;
	return () if $m->{command} =~ /^\d+$|^PING$/;
	push @{$self->{logs}}, [ time, $m ];
	return ();
} #}}}
sub load { #{{{
	my ($self, $data) = @_;
	$self->{logs} = $data;
} #}}}
sub save { #{{{
	my $self = $_[0];
	my $data = $self->{logs};
	return $data;
} #}}}

1;
