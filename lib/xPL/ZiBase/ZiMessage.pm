

package ZiMessage;

use Socket;
use WWW::Mechanize;



my $zibase_commands = {
  'off' => 0,
  'on'  => 1,
  'dim' => 2,
  'bright' => 2,
  'all_lights_on' => 4,
  'all_lights_off' => 5,
  'all_off' => 6,
  'assoc' => 7,
  'unassoc' =>8,
};

my $zibase_protocol = {
  'preset' => 0,
  'visonic433' => 1,
  'visonic868' => 2,
  'chacon' => 3,
  'domia' => 4,
  'x10' => 5,
  'zwave' => 6,
  'rfs10' => 7,
  'xdd433' => 8,
  'xdd433alrm' => 8,
  'xdd868' => 9,
  'xdd868alrm' => 9,
  'xdd868insh' => 10,
  'xdd868piwi' => 11,
  'xdd868boac' => 12,
};

my $zibase_vpprotocol = {
  'oregon' => 17,
  'owl'  => 20,
};

my $zibase_vptype = {
  'temp_sensor' => 0,
  'temp_hum_sensor' => 1,
  'power_sensor' => 2,
  'water_sensor' => 3,
}; 
  
# new()
sub new
{
  my $class = shift;
  my $self = {
    _sig => "ZSIG",
    _command => 0,
    _reserved1 => "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    _zibase_id => "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    _reserved2 => "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
	_param1 => 0,
    _param2 => 0,
    _param3 => 0,
    _param4 => 0,
    _my_count => 0,
    _your_count => 0,
	_command_text => "",
  };

  bless $self, $class;
  return $self;
}


=head2 C<getBinaryMessage( )>

This method returns the raw packet string that should be sent to the ZiBase

=cut

sub getBinaryMessage {
  my ($self) = @_;

  my $data = "ZSIG";

  $data .= pack('n', $self->{_command});
  $data .= $self->{_reserved1};
  $data .= $self->{_zibase_id};
  $data .= $self->{_reserved2};
  $data .= pack('NNNN', $self->{_param1}, $self->{_param2}, $self->{_param3}, $self->{_param4});
  $data .= pack('nn', $self->{_my_count}, $self->{_your_count});
  if ($self->{_command_text} ne "") {
    $data .= pack ('a96',$self->{_command_text});
  }

  return ($data);
}

=head2 C<fromPayload($payload)>

This method initializes the ZiMessage object with the given raw packet payload
Payload generally is a UDP packet received from the zibase.

=cut

sub fromPayload {
  my ($self, $payload) = @_;

  my @upa = unpack("A4 n A16 A16 A12 N N N N n n A*", $payload);
	    
  $self->{_sig} = $upa[0];	    
  $self->{_command} = $upa[1];
  $self->{_reserved1} = $upa[2];
  $self->{_zibase_id} = $upa[3];
  $self->{_reserved2} = $upa[4];
  $self->{_param1} = $upa[5];
  $self->{_param2} = $upa[6];
  $self->{_param3} = $upa[7];
  $self->{_param4} = $upa[8];
  $self->{_my_count} = $upa[9];
  $self->{_your_count} = $upa[10];
  $self->{_message} = $upa[11];	    
}


=head2 C<is_ack()>

Returns true if the ZiMessage is a ACK message.
Returns false otherwise.

=cut

sub is_ack {
  my ($self) = @_;

  return ($self->{_command} == 14) ? 1 : 0;
}

=head2 C<is_rfreceive()>

Returns true if the ZiMessage is a RF Receive type command packet.
Returns false otherwise.

=cut

sub is_rfreceive {
  my ($self) = @_;

  return ($self->{_command} == 3) ? 1 : 0;
}

=head2 C<setRegisterHost($ip, $port)>

Sets the ZiMessage to be a Register Host zibase message

=cut

sub setRegisterHost {
  my ($self, $ip, $port) = @_;

  $self->{_command} = 13;
  $self->{_param1} = unpack("N*", inet_aton($ip));
  $self->{_param2} = $port;
  $self->{_param3} = 0;
  $self->{_param4} = 0;
  #$self->{_reserved1} = "ZapiInit\x00\x00\x00\x00\x00\x00\x00\x00";
}

=head2 C<setunRegisterHost($ip, $port)>

Sets the ZiMessage to  Unregister the Host zibase from the Zibase (not used for the moment)

=cut

sub setUnRegisterHost {
  my ($self, $ip, $port) = @_;

  $self->{_command} = 22;
  $self->{_param1} = unpack("N*", inet_aton($ip));
  $self->{_param2} = $port;
  $self->{_param3} = 0;
  $self->{_param4} = 0;
}

=head2 C<setRFCommand($command, $protocol, $level, $nbrepeat)>

Sets the ZiMessage to be a RF command send message with the given
parameters :
  command should be one of [on|off|dim]
  level should be a number between 0 and 100 (only used if command=dim)
  nbrepeat sets the desired packet repetitions

=cut

sub setRFCommand {
  my ($self, $command, $protocol, $level, $nbrepeat, $peeraddr) = @_;
  
  # Sets global command type
  $self->{_command} = 11;
  $self->{_param1} = 0;

  # Sets the HA command code
  my $prm = $zibase_commands->{lc($command)};
  
  # Sets the Protocol code
  my $proto = $zibase_protocol->{lc($protocol)};
  if ($proto eq 6 and $prm == $zibase_commands->{'dim'}){
    my $www = WWW::Mechanize->new;
	$device = lc($device);
	$url = 'http://'.$peeraddr.'/cgi-bin/domo.cgi?cmd= DIM '.$device.' P6 '.$level.'';
    $www->put( $url);
	print $www->content();
	
  } else {
    $prm = $prm | (($proto) << 8);

    # Sets the dim level if needed
    if ($prm == $zibase_commands->{'dim'}) {
      $prm = $prm | (($level)  << 16);
    }

    # Sets the burst if specified
    if (defined($nbrepeat) && $nbrepeat > 1) {
      $prm = $prm | (($nbrepeat) << 24);
    }
  }
  $self->{_param2} = $prm;

}

=head2 C<setRFexecScenario($scenario)>

Sets the ZiMessage to be a RF command send message with the given
parameters :
  scenario should be the number of scenario you would be launch 

=cut

sub setRFexecScenario {
  my ($self, $scenario) = @_;

  # Sets global command type
  $self->{_command} = 11;
  $self->{_param1} = 1;
  $self->{_param2} = $scenario;
}

=head2 C<setRFexecScript($script)>

Sets the ZiMessage to be a RF command send message with the given
parameters :
  script to be launch by zibase

=cut

sub setRFexecScript {
  my ($self, $script) = @_;

  # Sets global command type
  $self->{_command} = 16;
  $self->{_command_text} = $script;
  }

=head2 C<setVPEvent($id, $type, $c1, $c2, $batt)>



=cut

sub setVPEvent {
  my ($self, $id, $type, $c1, $c2, $batt) = @_;

  # Sets global command type
  $self->{_command} = 11;
  $self->{_param1} = 6;
  
  # Sets Virtual probe type 
  my $vptype = $zibase_vptype->{lc($type)};
  
  if ($vptype ne '2') {
    $self->{_param4} = $zibase_vpprotocol->{'oregon'};
	# THN132 oregon temperature
	if ($vptype eq '0') {
	$self->{_param2} = (0x1) << 16| $id;
	}
	# THGR228 oregon temperature/humidity
	if ($vptype eq '1') {
	$self->{_param2} = (0x1a2d) << 16| $id;
	}
	# Water sensor oregon
	if ($vptype eq '3') {
	$self->{_param2} = (0x2a19) << 16| $id;
	}
  } else {
    # Power meter OWL 
	$self->{_param4} = $zibase_vpprotocol->{'owl'};   
    $self->{_param2} = (0x2) << 16| $id;  
  }
  
  #set values  
  $prm = $c1;
  $prm = $prm | ($c2) << 16;
  $prm = $prm | ($batt) << 26;
  $self->{_param3} = $prm;
}


=head2 C<setRFAddress($address)>

Sets the ZiMessage x10 address. Only applicable to RF Send messages.
parameters :
  address is a string representing the x10-like address (a5, p10...)

=cut

sub setRFAddress {
  my ($self, $device) = @_;

  my ($nb1, $nb2) = $self->decode_x10_address($device);
  $self->{_param3} = $nb2;
  $self->{_param4} = $nb1;
}

=head2 C<decode_x10_address($address)>

Decodes the given x10 address in string format to integers.
Returns an array of two integers representing the house and unit codes.

=cut

sub decode_x10_address {
  my ($self, $address) = @_;

  #$device = lc($device);
  my $nb1 = ord($address) - ord('a');
  my $nb2 = int(substr($address, 1)) - 1;
  return ($nb1, $nb2);
}

__END__

