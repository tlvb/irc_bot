use warnings;
use strictures 2;

package IRCBot::ConfigReader;

sub read { #{{{
	my $fn = shift;

	open my $fd, '<', $fn or die "CONFIG ERROR:\nCould not open config file '$fn':\n$!";
	my $configstr;
	{
		local $/ = undef;
		$configstr = '$config = {'.<$fd>.'};';
	}
	close $fd;

	my $config = {};
	eval $configstr;

	die "CONFIG ERROR:\n$@\n$!\n" if $@ ne '';

	return $config;
} #}}}
1;
