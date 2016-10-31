use warnings;
use strictures 2;
package IRCBot::Plugin::Loader;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;
use IRCBot::DayLog;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.1.0-debug',);
	bless $self, $class;

	return $self;

} #}}}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	$self->log_d($e->deflate);
	if ($e->type eq 'ACL-RESPONSE') {
		$self->log_d('directed acl response');
		my $p = $e->{data}->{parsed};
		if (defined $e->{acl_data}) {
			if ($e->{acl_data}->{trust} == 2) {
				my ($action, $plugin) = @{$e->{data}->{action}};
				$self->emit_event(
					origin=>'loader',
					target=>'broker',
					type=>"PLUGIN-".uc($action),
					plugin=>lc($plugin),
					notify=>{respond=>$p->{respond_target}, address=>$p->{respond_prefix}});
				}
			else {
				$self->emit_message(
					command=>'PRIVMSG',
					params=>[$p->{respond_target}, $p->{respond_prefix}."Access denied."]);
			}
		}
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	if ($m->c eq 'PRIVMSG') {
		my $p = $self->decode_privmsg($m);
		if ($p->{addressed} > 0 && $p->{message} =~ /((?:re|un)?load)\s+([0-9A-Za-z_]+)\s*$/) {
			my $action = $1;
			my $plugin = $2;
			$self->log_d("match $action $plugin");
			$self->emit_event(target=>'acl', origin=>'loader', type=>'ACL-QUERY', nick=>$m->{name}, data=>{parsed=>$p, action=>[$action, $plugin]});
		}
	}
} #}}}
1;
