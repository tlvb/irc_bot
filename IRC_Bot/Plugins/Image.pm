use strict;
use warnings;
no warnings 'redefine';

package IRC_Bot::Plugins::Image;
use HTML::Entities;
use POSIX;
use utf8;

sub new { #{{{
	my ($class, $botstate) = @_;
	my $self = {
		urlpart=>qr/(?:[-\._~:\/\?#\[\]\@!\$\&'\(\)\*\+,;=A-Za-z0-9]|%(?:[0-9A-Fa-f]{2}))/,
		curlbinary=> $^O eq 'openbsd' ? '/usr/local/bin/curl' : '/usr/bin/curl',
		blockimgbinary=> $^O eq 'openbsd' ? '/home/leo/blockimg/blockimg' : '/home/leo/sw/blockimg/blockimg'
	};
	bless $self, $class;
	return $self;
} #}}}
sub try_fetch_image { #{{{
	my ($self, $trg, $type, $url) = @_;
	my $fd;
	my @ret;
	# check content type!
	print STDERR "fetching header to extract content-type\n";
	open $fd, '-|', $self->{curlbinary}, '-I', '-A', 'Mozilla', '-sLm7', $url;
	my $header;
	{
		local $/ = undef;
		$header = <$fd>;
	}
	close $fd;
	print STDERR "$header\n";
	if ($header !~ /Content-Type: image\//) {
		push @ret, ['PRIVMSG', $trg, 'not an image link'];
		return @ret;
	}
	print STDERR "image url: $url\n";
	open $fd, '-|', $self->{curlbinary}, '-o', '/tmp/irc_bot_plugin_image', '-A', 'Mozilla', '--max-filesize', '10485760', '-sLm15', $url;
	my $nothing;
	{
		local $/ = undef;
		$nothing = <$fd>;
	}
	close $fd;
	$type = 'm' if $type eq 'c';

	open $fd, '-|', $self->{blockimgbinary}, "-s$type", '120', '24', '/tmp/irc_bot_plugin_image';
	for my $line (<$fd>) {
		chomp $line;
		push @ret, ['PRIVMSG', $trg, $line];
	}
	close $fd;
	#unlink '/tmp/ircbot_plugin_image';
	return @ret;
} #}}}
sub handle_input { #{{{
	my $self = shift;
	my $m = shift;
	my $mynick = shift;
	my @ret = ();
	return () unless $m->{command} eq 'PRIVMSG'; # only extract links from messages
	if (@_) {
		# ( trg who comm params... )
		if (lc $_[2] eq 'help' and lc $_[3] eq 'image') {
			push @ret, ['PRIVMSG', $_[0], "$_[1]: .image b|g|c url -- fetches an image and displays it in monochrome, gray, or color"]
		}
		if (lc $_[2] eq 'image' and $_[3] =~ /^([bgc]) (https?:\/\/$self->{urlpart}+)/) {
			my $t = time;
			if (exists $self->{time} and $t - $self->{time} < 300) {
				push @ret, ['PRIVMSG', $_[0], "$_[1]: sorry, there's a five minute cooldown to avoid flooding"]
			}
			else {
				print STDERR "cheese TYPE: '$1' URL: '$2'\n";
				@ret = $self->try_fetch_image($_[0], $1, $2);
				$self->{time} = $t;
			}
		}
	}
	return @ret;
} #}}}

1;

