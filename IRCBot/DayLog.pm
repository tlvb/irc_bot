use warnings;
use strictures 2;
package IRCBot::DayLog;

sub regular { return "\x1b[0m";  }
sub bold    { return "\x1b[1m";  }
sub black   { return "\x1b[30m"; }
sub red     { return "\x1b[31m"; }
sub green   { return "\x1b[32m"; }
sub yellow  { return "\x1b[33m"; }
sub blue    { return "\x1b[34m"; }
sub magenta { return "\x1b[35m"; }
sub cyan    { return "\x1b[36m"; }
sub white   { return "\x1b[37m"; }

sub log { #{{{
	my $type = shift;
	my $line = shift;

	$type = ['', $type, ''] unless ref $type eq 'ARRAY';
	die "undef line from of type $type->[1]. caller: ".join(' ', caller) unless defined $line;
	my $line_nf = $line =~ s/\x1b\[\d+m//gr;

	my $red = red();
	my $yellow = yellow();
	my $green = green();
	my $regular = regular();
	$line =~ s/\bUNKNOWN\b|\bWARNING\b/$yellow$&$regular/g;
	$line =~ s/\bERROR\b|\bFAILURE\b/$red$&$regular/g;
	$line =~ s/\bOK\b|\bSUCCESS\b/$green$&$regular/g;

	my ($sec,$min,$hour,$mday,$mon,$year,@dontcare) = localtime;
	$year += 1900;
	$mon += 1;
	my $date = sprintf '%04d.%02d.%02d', $year, $mon, $mday;
	my $time = sprintf '%02d:%02d:%02d', $hour, $min, $sec;

	my $tagged_line = sprintf '[%s/%s][%s%-16s%s] %s'."\n", $date, $time, @$type, $line;
	my $tagged_line_nf = sprintf '[%s/%s][%-16s] %s'."\n", $date, $time, $type->[1], $line_nf;

	print $tagged_line;
	open my $fd, '>>:encoding(UTF-8)', "log/log.$date" or die "log 'log/log.$date'\n$!";
	print $fd $tagged_line_nf;
	close $fd;
} #}}}
1;
