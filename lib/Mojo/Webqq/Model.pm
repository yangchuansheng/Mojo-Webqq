package Mojo::Webqq::Model;
use strict;
use List::Util qw(first);
use Mojo::Webqq::User;
use Mojo::Webqq::Friend;
use Mojo::Webqq::Group;
use Mojo::Webqq::Discuss;
use Mojo::Webqq::Discuss::Member;
use Mojo::Webqq::Group::Member;
use Mojo::Webqq::Model::Remote::_get_user_info;
use Mojo::Webqq::Model::Remote::get_single_long_nick;
use Mojo::Webqq::Model::Remote::get_qq_from_id;
use Mojo::Webqq::Model::Remote::_get_user_friends;
use Mojo::Webqq::Model::Remote::_get_user_friends_ext;
use Mojo::Webqq::Model::Remote::_get_friends_state;
use Mojo::Webqq::Model::Remote::_get_group_list_info;
use Mojo::Webqq::Model::Remote::_get_group_list_info_ext;
use Mojo::Webqq::Model::Remote::_get_group_info;
use Mojo::Webqq::Model::Remote::_get_group_info_ext;
use Mojo::Webqq::Model::Remote::_get_discuss_info;
use Mojo::Webqq::Model::Remote::_get_discuss_list_info;
use Mojo::Webqq::Model::Remote::_get_recent_info;
use Mojo::Webqq::Model::Remote::_invite_friend;
use Mojo::Webqq::Model::Remote::_set_group_admin;
use Mojo::Webqq::Model::Remote::_remove_group_admin;
use Mojo::Webqq::Model::Remote::_kick_group_member;
use Mojo::Webqq::Model::Remote::_set_group_member_card;
use Mojo::Webqq::Model::Remote::_shutup_group_member;

use base qw(Mojo::Webqq::Base);

sub hash {
    my $self = shift;
    my $ptwebqq = shift;
    my $uin = shift;

    $uin .= "";
    my @N;
    for(my $T =0;$T<length($ptwebqq);$T++){
        $N[$T % 4] ^= ord(substr($ptwebqq,$T,1));
    }
    my @U = ("EC", "OK");
    my @V;
    $V[0] =  $uin >> 24 & 255 ^ ord(substr($U[0],0,1));
    $V[1] =  $uin >> 16 & 255 ^ ord(substr($U[0],1,1));
    $V[2] =  $uin >> 8  & 255 ^ ord(substr($U[1],0,1));
    $V[3] =  $uin       & 255 ^ ord(substr($U[1],1,1));
    @U = ();
    for(my $T=0;$T<8;$T++){
        $U[$T] = $T%2==0?$N[$T>>1]:$V[$T>>1]; 
    }
    @N = ("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F");
    my $V = "";
    for(my $T=0;$T<@U;$T++){
        $V .= $N[$U[$T] >> 4 & 15];
        $V .= $N[$U[$T] & 15];
    }

    return $V;
}

sub is_support_model_ext {
    my $self = shift;
    return 1 if $self->model_ext;
    my $ret = $self->search_cookie("p_skey") && $self->search_cookie("skey");
    $self->model_ext($ret || 0);
    return $ret;
}
sub get_model_status{
    my $self = shift;
    if(     defined $self->model_status->{friend} 
        and defined $self->model_status->{group}
    ){
        my $is_fail =
                $self->model_status->{friend} == 0
            &&  $self->model_status->{group} == 0
        ;
        return $is_fail?0:1;
    }
    else{
        return -1;
    }
}
sub get_csrf_token {
    use integer;
    my $self = shift;
    if(not $self->is_support_model_ext){
        $self->error("当前不支持获取扩展信息，无法获取CSRF Token");
        return;
    }
    return $self->csrf_token if defined $self->csrf_token;
    my $t = $self->search_cookie("skey");
    my $n = 0;
    my $o=length($t);
    my $r;
    if($t){
        for($r=5381;$o>$n;$n++){
            $r += ($r<<5) + ord(substr($t,$n,1));
        }
        my $token = 2147483647 & $r;
        $self->csrf_token($token);
        return $token;
    } 
}
sub each_friend{
    my $self = shift;
    my $callback = shift;
    $self->die("参数必须是函数引用") if ref $callback ne "CODE";
    $self->update_friend(is_blocking=>1,is_update_friend_ext=>1) if @{$self->friend} == 0;
    for (@{$self->friend}){
        $callback->($self,$_);   
    }
}
sub each_group{
    my $self = shift;
    my $callback = shift;
    $self->die("参数必须是函数引用") if ref $callback ne "CODE";
    $self->update_group(is_blocking=>1,is_update_group_member=>0) if @{$self->group} == 0;
    for (@{$self->group}){
        $callback->($self,$_);     
    }
}

sub each_discuss{
    my $self = shift;
    my $callback = shift;
    $self->die("参数必须是函数引用") if ref $callback ne "CODE";
    $self->update_discuss(is_blocking=>1,is_update_discuss_member=>0) if @{$self->discuss} == 0;
    for (@{$self->discuss}){
        $callback->($self,$_);
    }
}
sub each_group_member{
    my $self = shift;
    my $callback = shift;
    $self->die("参数必须是函数引用") if ref $callback ne "CODE";
    if(@{$self->group} == 0){
        $self->update_group(is_blocking=>1,is_update_group_member=>1);
    }
    else{
        for( @{$self->group}){
            $_->upadte_group_member(is_blocking=>1,) if $_->is_empty;   
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->group};
    for (@member){
        $callback->($self,$_);
    }
}
sub each_discuss_member{
    my $self = shift;
    my $callback = shift;
    $self->die("参数必须是函数引用") if ref $callback ne "CODE";
    if(@{$self->discuss} == 0){
        $self->update_discuss(is_blocking=>1,is_update_discuss_member=>1);
    }
    else{
        for( @{$self->discuss}){
            $_->upadte_discuss_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->discuss};
    for (@member){
        $callback->($self,$_);
    }
}

sub update_user {
    my $self = shift;
    my $is_blocking = ! shift;
    $self->info("更新个人信息...\n");
    my $handle = sub{
        my $user_info = shift;
        unless ( defined $user_info ) {
            $self->warn("更新个人信息失败\n");
            $self->user($self->new_user({id=>$self->qq,qq=>$self->qq}));
            $self->emit("model_update"=>"user",0);
            return;
        }       
        $self->user($self->new_user($user_info));
        $self->emit("model_update"=>"user",1);
    };
    if($is_blocking){
        my $user_info = $self->_get_user_info();
        $handle->($user_info);
    } 
    else{
        $self->_get_user_info($handle);
    }
}

sub remove_friend {
    my $self = shift;
    my $friend = shift;
    $self->die("不支持的数据类型\n") if ref $friend ne "Mojo::Webqq::Friend";
    for(my $i=0;@{$self->friend};$i++){
        if($friend->id eq $self->friend->[$i]->id){
            splice @{$self->friend},$i,1;
            return 1; 
        }
    }
    return 0;
}
sub add_friend {
    my $self = shift;
    my $friend = shift;
    my $nocheck = shift;
    $self->die("不支持的数据类型\n") if ref $friend ne "Mojo::Webqq::Friend";
    if(@{$self->friend}  == 0){
        push @{$self->friend},$friend;
        return $self;
    }
    if($nocheck){
        push @{$self->friend},$friend;
        return $self;
    }
    my $f = $self->search_friend(id => $friend->id);
    if(defined $f){
        %$f = %$friend;
    }
    else{
        push @{$self->friend},$friend;
    }
    return $self;
}

sub update_friend_ext {
    my $self = shift;
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    $self->info("更新好友扩展信息...\n");
    my $handle = sub{
        my $friends_ext_info = shift;
        if(defined $friends_ext_info and ref $friends_ext_info eq "ARRAY"){
            my(undef,$ext)=$self->array_unique($friends_ext_info,sub{"$_[0]->{nick}|$_[0]->{category}"});
            my $unique_friend = $self->array_unique($self->friend,sub{$_[0]->nick . "|" . $_[0]->category});
            for(@$unique_friend){
                my $id = $_->nick . "|" . $_->category;
                next if not exists $ext->{$id};
                $_->{qq} = $ext->{$id}{qq};
            }
            $self->emit("model_update"=>"friend_ext",1);
        }
        else{
            $self->warn("更新好友扩展信息失败");
            $self->emit("model_update"=>"friend_ext",0);
        }
    };
    if($p{is_blocking}){
        my $friends_ext_info = $self->_get_user_friends_ext();
        $handle->($friends_ext_info);
    }
    else{
        $self->_get_user_friends_ext($handle);    
    }
}
sub update_friend {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Friend"){
        my $friend = shift;
        my %p = @_;
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        $self->info("更新好友 [ " . $friend->nick .  " ] 信息...");
        my $handle = sub{
            my $friend_info = shift;
            if(defined $friend_info){$friend->update($friend_info);}
            else{$self->warn("更新好友 [ " . $friend->nick .  " ] 信息失败...");}
        };
        if($p{is_blocking}){
            my $friend_info = $self->_get_friend_info($friend->id);
            $handle->($friend_info);
        }
        else{
            $self->_get_friend_info($friend->id,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_friend_ext} = 1 if not defined $p{is_update_friend_ext};
    $self->info("更新好友信息..."); 
    my $handle = sub{
        my @friends;
        my $friends_info = shift;
        if(defined $friends_info){
            push @friends,$self->new_friend($_) for @{$friends_info};
            if(ref $self->friend eq "ARRAY" and @{$self->friend}  == 0){
                $self->friend(\@friends);
            }
            else{
                my($new_friends,$lost_friends,$sames) = $self->array_diff($self->friend,\@friends,sub{$_[0]->id});
                for(@{$new_friends}){
                    $self->add_friend($_);
                    $self->emit(new_friend=>$_);
                }
                for(@{$lost_friends}){
                    $self->remove_friend($_);
                    $self->emit(lose_friend=>$_);
                }
                for(@{$sames}){
                    my($old,$new) = @$_;
                    $old->update($new);
                }
            }
            $self->emit("model_update","friend",1);
            $self->update_friend_ext(is_blocking=>$p{is_blocking}) if $p{is_update_friend_ext};
        }
        else{$self->warn("更新好友信息失败");$self->emit("model_update","friend",0);}
    };
    if($p{is_blocking}){
        my $friends_info = $self->_get_user_friends();
        $handle->($friends_info);
    }
    else{
        $self->_get_user_friends($handle);
    }
}
sub search_friend {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_friend(is_blocking=>1,is_update_friend_ext=>1) if @{ $self->friend } == 0;
    if(wantarray){
        return grep {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->friend};
    }
    else{
        return first {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->friend};
    }
}

sub add_group{
    my $self = shift;
    my $group = shift;
    my $nocheck = shift;
    $self->die("不支持的数据类型") if ref $group ne "Mojo::Webqq::Group";
    if(@{$self->group}  == 0){
        push @{$self->group},$group;
        return $self;
    }
    if($nocheck){
        push @{$self->group},$group;
        return $self;
    }
    my $g = $self->search_group(gid => $group->gid);
    if(defined $g){
        %$g = %$group;
    }
    else{#new group
        push @{$self->group},$group;
    }
    return $self;
}
sub remove_group{
    my $self = shift;
    my $group = shift;
    $self->die("不支持的数据类型") if ref $group ne "Mojo::Webqq::Group";
    for(my $i=0;@{$self->group};$i++){
        if($group->gid eq $self->group->[$i]->gid){
            splice @{$self->group},$i,1;
            return 1;
        }
    }
    return 0;
}
sub update_group_ext {
    my $self = shift;
    my $group;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    return if @{ $self->group } == 0;
    $group = shift if ref $_[0] eq "Mojo::Webqq::Group";
    $self->info("更新群扩展信息...");
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_group_member_ext} = 1 if not defined $p{is_update_group_member_ext};

    my $handle = sub{
        my $group_list_ext = shift;
        if(defined $group_list_ext and ref $group_list_ext eq "ARRAY"){
            my(undef,$gext)= $self->array_unique($group_list_ext,sub{$_[0]->{gname}});
            my $unique_group = $self->array_unique($self->group,sub{$_[0]->gname}); 
            my @groups = defined $group?(grep {$_->gid eq $group->gid} @$unique_group) : @$unique_group;
            for my $g (@groups){
                my $id = $g->gname;
                next if not exists $gext->{$id};
                #$g->{gtype} = $gext->{$id}{gtype};
                #$g->{gnumber} = $gext->{$id}{gnumber};
                $g->update($gext->{$id});
                $self->update_group_member_ext($g,%p) if $p{is_update_group_member_ext};
            }
            $self->emit("model_update","group_ext",1);
        }
        else{$self->warn("更新群扩展信息失败");$self->emit("model_update","group_ext",0);}
    };
    if($p{is_blocking}){
        my $group_list_ext = $self->_get_group_list_info_ext();
        $handle->($group_list_ext);   
    }
    else{
        $self->_get_group_list_info_ext($handle);
    }
}
sub update_group_member_ext {
    my $self = shift;
    my $group = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("群组[ ". $group->gname . " ]当前无法支持获取扩展信息");
        return;
    }
    $self->die("不支持的数据类型") if ref $group ne "Mojo::Webqq::Group";
    if(not defined $group->gnumber){
        $self->warn("群组[ ". $group->gname . " ]未包含有效的gnumber，无法更新群成员扩展信息");
        return;
    }
    if($group->is_empty){
        $self->warn("群组[ ". $group->gname . " ]未包含群成员，忽略更新群成员扩展信息");
        return;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $self->info("更新群组[ ". $group->gname . " ]成员扩展信息");
    my $handle = sub{
        my $group_info_ext = shift;
        if(defined $group_info_ext){
            my(undef,$mext) = $self->array_unique($group_info_ext->{member},sub{ $_[0]->{nick} . (defined($_[0]->{card})?$_[0]->{card}:"") . $_[0]->{gender}});
            my $unique_member = $self->array_unique($group->member,sub{$_[0]->nick . (defined($_[0]->card)?$_[0]->card:"") . $_[0]->gender});
            for(@$unique_member){
                my $id = $_->nick . (defined($_->card)?$_->card:"") . $_->gender;
                next if not exists $mext->{$id};
                #$_->{qage} = $mext->{$id}{qage};
                #$_->{level} = $mext->{$id}{level};
                #$_->{bad_record} = $mext->{$id}{bad_record};
                #$_->{qq} = $mext->{$id}{qq};
                #$_->{role} = $mext->{$id}{role};
                #$_->{join_time} = $mext->{$id}{join_time};
                #$_->{last_speak_time} = $mext->{$id}{last_speak_time};
                $_->update($mext->{$id});
                $_->{gtype} = $group->gtype;
                $_->{gnumber} = $group->gnumber || $mext->{$id}->{gnumber};
            }
            $self->emit("model_update","group_member_ext",1);
        }
        else{$self->warn("更新群组[ " . $group->gname . " ]成员扩展信息失败");}
    }; 
    if($p{is_blocking}){
        my $group_info_ext = $self->_get_group_info_ext($group->gnumber);
        $handle->($group_info_ext);
    }
    else{
        $self->_get_group_info_ext($group->gnumber,$handle);
    }
    
}
sub update_group_member {
    my $self = shift;
    my $group = shift;
    $self->die("不支持的数据类型") if ref $group ne "Mojo::Webqq::Group";
    $self->info("更新群组[ ". $group->gname . " ]成员信息");
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $p{is_update_group_member_ext} = 1 if not defined $p{is_update_group_member_ext};
    my $handle = sub{
        my $group_info = shift;
        if(defined $group_info){ 
            if(ref $group_info->{member} eq 'ARRAY'){
                $group->update($group_info); 
                #$self->update_group_member_ext($group,%p) if $p{is_update_group_member_ext};
            }
            else{$self->debug("更新群组[ " . $group->gname . " ]成员信息无效")}
        }
        else{$self->warn("更新群组[ " . $group->gname . " ]成员信息失败")}
        
    };
    if($p{is_blocking}){
        my $group_info = $self->_get_group_info($group->gcode);
        $handle->($group_info);
    }
    else{
        $self->_get_group_info($group->gcode,$handle);
    }
}
sub update_group {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Group"){
        my $group = shift;
        my %p = @_;
        $self->info("更新群组[ ". $group->gname . " ]信息");
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        $p{is_update_group_member} = 1 if not defined $p{is_update_group_member} ;
        $p{is_update_group_ext} = $p{is_blocking} if not defined $p{is_update_group_ext} ;
        $p{is_update_group_member_ext} = $p{is_update_group_ext} && $p{is_blocking}  if not defined $p{is_update_group_member_ext} ;
        my $handle = sub{
            my $group_info = shift;
            if(defined $group_info){
                if(ref $group_info->{member} eq 'ARRAY'){
                    $group->update($group_info);
                    $self->update_group_ext($group,%p) if $p{is_update_group_ext};
                }
                else{$self->debug("更新群组[ " . $group->gname . " ]成员信息无效")}
            }
            else{$self->warn("更新群组[ " . $group->gname . " ]成员信息失败")}

        };
        if($p{is_blocking}){
            my $group_info = $self->_get_group_info($group->gcode);
            $handle->($group_info);
        }
        else{
            $self->_get_group_info($group->gcode,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    $p{is_update_group_member} = 1 if not defined $p{is_update_group_member} ;
    $p{is_update_group_ext} = $p{is_blocking} if not defined $p{is_update_group_ext} ;
    $p{is_update_group_member_ext} = $p{is_blocking} && $p{is_update_group_ext} && $p{is_update_group_member} if not defined $p{is_update_group_member_ext} ;
    $self->info("更新群列表信息...");
    my $handle = sub{
        my @groups;
        my $group_list = shift; 
        unless(defined $group_list){
            $self->warn("更新群列表信息失败\n");
            $self->emit("model_update","group",0);
            return $self;
        }
        for my $g (@{$group_list}){
            push @groups, $self->new_group($g);
        } 
        if(ref $self->group eq "ARRAY" and @{$self->group} == 0){
            $self->group(\@groups);
        }
        else{
            my($new_groups,$lost_groups,$sames) = $self->array_diff($self->group,\@groups,sub{$_[0]->gid});  
            for(@{$new_groups}){
                $self->add_group($_);
                $self->emit(new_group=>$_) ;
            }
            for(@{$lost_groups}){
                $self->remove_group($_);
                $self->emit(lose_group=>$_) ;
            }
            for(@{$sames}){
                my($old_group,$new_group) = ($_->[0],$_->[1]);
                $old_group->update($new_group); 
            }
        }
        $self->emit("model_update","group",1);
        if($p{is_update_group_member}){
            for(@{ $self->group }){
                $self->update_group_member($_,%p);
            }
        }
        if($p{is_update_group_ext}){
            $self->update_group_ext(%p);
        }
    };
    if($p{is_blocking}){
        my $group_list = $self->_get_group_list_info(); 
        $handle->($group_list);
    }
    else{
        $self->_get_group_list_info($handle);
    }
}

sub search_group {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_group(is_update_group_member=>0) if @{ $self->group } == 0;
    delete $p{member};
    delete $p{_client};
    if(wantarray){
        return grep {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->group};
    }
    else{
        return first {my $g = $_;(first {$p{$_} ne $g->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->group};
    }
}

sub search_group_member {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(@{$self->group} == 0){
        $self->update_group(is_blocking=>1,is_update_group_member=>1);
    }
    else{
        for( @{$self->group}){
            $_->upadte_group_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->group};
    if(wantarray){
        return grep {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
    else{
        return first {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
}

sub add_discuss {
    my $self = shift;
    my $discuss = shift;
    my $nocheck = shift;
    $self->die("不支持的数据类型") if ref $discuss ne "Mojo::Webqq::Discuss";
    if(@{$self->discuss}  == 0){
        push @{$self->discuss},$discuss;
        return $self;
    }
    if($nocheck){
        push @{$self->discuss},$discuss;
        return $self;
    }
    my $d = $self->search_discuss(did => $discuss->did);
    if(defined $d){
        %$d = %$discuss;
    }
    else{#new discuss
        push @{$self->discuss},$discuss;
    }
    return $self;

}
sub remove_discuss {
    my $self = shift;
    my $discuss = shift;
    $self->die("不支持的数据类型") if ref $discuss ne "Mojo::Webqq::Discuss";
    for(my $i=0;@{$self->discuss};$i++){
        if($discuss->did eq $self->discuss->[$i]->did){
            splice @{$self->discuss},$i,1;
            return 1;
        }
    }
    return 0;
}

sub add_discuss_member {}

sub update_discuss_member{
    my $self = shift;
    my $discuss = shift; 
    $self->die("不支持的数据类型") if ref $discuss ne "Mojo::Webqq::Discuss";
    $self->info("更新讨论组[ ". $discuss->dname . " ]成员信息");
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    my $handle = sub{
        my $discuss_info = shift;
        if(defined $discuss_info){
            if(ref $discuss_info->{member} eq 'ARRAY'){
                $discuss->update($discuss_info);
            }
            else{$self->debug("更新讨论组[ " . $discuss->dname . " ]成员信息无效")}
        }
        else{$self->warn("更新讨论组[ " . $discuss->dname . " ]成员信息失败")}
    };

    if($p{is_blocking}){
        my $discuss_info = $self->_get_discuss_info($discuss->did);
        $handle->($discuss_info);
    }
    else{
        $self->_get_discuss_info($discuss->did,$handle);
    }
    
}
sub update_discuss {
    my $self = shift;
    if(ref $_[0] eq "Mojo::Webqq::Discuss"){
        my $discuss = shift;
        my %p = @_;
        $self->info("更新讨论组[ ". $discuss->dname . " ]信息");
        $p{is_blocking} = 1 if not defined $p{is_blocking};
        my $handle = sub{
            my $discuss_info = shift;
            if(defined $discuss_info){
                if(ref $discuss_info->{member} eq 'ARRAY'){
                    $discuss->update($discuss_info);
                }
                else{$self->debug("更新讨论组[ " . $discuss->gname . " ]成员信息无效")}
            }
            else{$self->warn("更新讨论组[ " . $discuss->dname . " ]成员信息失败")}

        };
        if($p{is_blocking}){
            my $discuss_info = $self->_get_discuss_info($discuss->did);
            $handle->($discuss_info);
        }
        else{
            $self->_get_discuss_info($discuss->did,$handle);
        }
        return $self;
    }
    my %p = @_;
    $p{is_blocking} = 1 if not defined $p{is_blocking} ;
    $p{is_update_discuss_member} = 1 if not defined $p{is_update_discuss_member} ;
    $self->info("更新讨论组列表信息...");
    my $handle = sub{
        my @discusss;
        my $discuss_list = shift;
        unless(defined $discuss_list){
            $self->warn("更新讨论列表信息失败\n");
            $self->emit("model_update","discuss",0);
            return $self;
        }
        for my $d (@{$discuss_list}){
            push @discusss, $self->new_discuss($d);
        }
        if(ref $self->discuss eq "ARRAY" and @{$self->discuss} == 0){
            $self->discuss(\@discusss);
        }
        else{
            my($new_discusss,$lost_discusss,$sames) = $self->array_diff($self->discuss,\@discusss,sub{$_[0]->did});
            for(@{$new_discusss}){
                $self->add_discuss($_);
                $self->emit(new_discuss=>$_) ;
            }
            for(@{$lost_discusss}){
                $self->remove_discuss($_);
                $self->emit(lose_discuss=>$_) ;
            }
            for(@{$sames}){
                my($old_discuss,$new_discuss) = ($_->[0],$_->[1]);
                $old_discuss->update($new_discuss);
            }
        }
        $self->emit("model_update","discuss",1);
        if($p{is_update_discuss_member}){
            for(@{ $self->discuss }){
                $self->update_discuss_member($_,%p);
            }
        }
    };
    if($p{is_blocking}){
        my $discuss_list = $self->_get_discuss_list_info();
        $handle->($discuss_list);
    }
    else{
        $self->_get_discuss_list_info($handle);
    }
}

sub search_discuss {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    $self->update_discuss(is_blocking=>1,is_update_discuss_member=>0) if @{$self->discuss} == 0;
    delete $p{member};
    delete $p{_client};
    if(wantarray){
        return grep {my $d = $_;(first {$p{$_} ne $d->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->discuss};
    }
    else{
        return first {my $d = $_;(first {$p{$_} ne $d->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->discuss};
    }
}

sub search_discuss_member {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(@{$self->discuss} == 0){
        $self->update_discuss(is_blocking=>1,is_update_discuss_member=>1);
    }
    else{
        for( @{$self->discuss}){
            $_->upadte_discuss_member(is_blocking=>1,) if $_->is_empty;
        }
    }
    my @member = map {@{$_->member}} grep {ref $_->member eq "ARRAY"}  @{$self->discuss};
    if(wantarray){
        return grep {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
    else{
        return first {my $m = $_;(first {$p{$_} ne $m->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @member;
    }
}

sub add_recent {
    my $self = shift;
    my $object = shift;
    return if not defined $object;
    my $o = $self->search_recent(id=>$object->id);
    if(defined $o){$o->update($object)}
    else{
        if(@{$self->recent} >= $self->max_recent){
            shift @{$self->recent};
        }
        push @{$self->recent},$object;
    }
    
}

sub update_recent {
    my $self = shift;
    my %p =@_;
    $p{is_blocking} = 1 if not defined $p{is_blocking};
    $self->info("更新最近联系人信息...\n");
    my $handle = sub{
        my $recent_info =  shift;
        if(defined $recent_info){
            for(@{$recent_info}){
                if($_->{type} eq "friend"){$self->add_recent($self->search_friend(id=>$_->{id}))}
                #elsif($_->{type} eq "group"){}
                #elsif($_->{type} eq "discuss"){}
            }
            $self->emit("model_update","recent",1);
        }
        else{
            $self->warn("更新最近联系人信息失败\n");
            $self->emit("model_update","recent",0);
        }
    };
    if($p{is_blocking}){
        my $recent_info = $self->_get_recent_info();
        $handle->($recent_info);
    }
    else{
        $self->_get_recent_info($handle);
    }
}

sub search_recent {
    my $self = shift;
    my %p = @_;
    return if 0 == grep {defined $p{$_}} keys %p;
    if(wantarray){
        return grep {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->recent};
    }
    else{
        return first {my $f = $_;(first {$p{$_} ne $f->$_} grep {defined $p{$_}} keys %p) ? 0 : 1;} @{$self->recent};
    }
}

sub invite_friend{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    my $group = shift;
    my @friends = @_;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法邀请好友入群");
        return;
    }
    if($group->me->gtype ne "manage" and $group->me->gtype ne "create"){
        $self->error("非群主或管理员，无法邀请好友入群");
        return;
    }
    for(@friends){
        $self->die("非好友对象") if not $_->is_friend;
    }
    my $ret = $self->_invite_friend($group->gnumber,map {$_->qq}  @friends);
    if($ret){$self->info("邀请好友入群成功")}
    else{$self->error("邀请好友入群失败")}
    return $ret;
}
sub kick_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法踢除群成员");
        return;
    }
    if($group->me->gtype ne "manage" and $group->me->gtype ne "create"){
        $self->error("非群主或管理员，无法踢除群成员");
        return;
    }
    for(@members){                                            
        $self->die("非群成员对象") if not $_->is_group_member;  
    }
    my $ret = $self->_kick_group_member($group->gnumber,map {$_->qq} @members);
    if($ret){
        for(@members){
            $_->group->remove_group_member($_);
            $self->emit(lose_group_member=>$_);
        }
        $self->info("踢除群成员成功");
    }
    else{$self->error("剔除群成员失败")}
    return $ret;
}

sub shutup_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    my $group = shift;
    my $time = shift;
    my @members = @_;
    if($time<60){
        $self->error("禁言时间太短，至少1分钟");
        return;
    }
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法完成禁言操作");
        return;
    }
    if($group->me->gtype ne "manage" and $group->me->gtype ne "create"){
        $self->error("非群主或管理员，无法完成禁言操作");
        return;
    }
    for(@members){
        $self->die("非群成员对象") if not $_->is_group_member;
        if($_->role eq "admin" or $_->role eq "owner"){
            $self->error("无法对群主或管理员进行禁言操作");
            return; 
        } 
    }
    my $ret = $self->_shutup_group_member($group->gnumber,$time,map {$_->qq} @members);
    if($ret){$self->info("禁言操作成功");}
    else{$self->error("禁言操作失败");}
    return $ret;
}
sub speakup_group_member{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法完成禁言操作");
        return;
    }
    if($group->me->gtype ne "manage" and $group->me->gtype ne "create"){
        $self->error("非群主或管理员，无法完成禁言操作");
        return;
    }
    for(@members){
        $self->die("非群成员对象") if not $_->is_group_member;
        if($_->role eq "admin" or $_->role eq "owner"){
            $self->error("无法对群主或管理员进行取消禁言操作");
            return; 
        } 
    }
    my $ret = $self->_shutup_group_member($group->gnumber,0,map {$_->qq} @members);
    if($ret){$self->info("取消禁言操作成功");}
    else{$self->error("取消禁言操作失败");}
    return $ret;
}
sub set_group_admin{
    my $self = shift;
    if ( not $self->is_support_model_ext){
        $self->warn("无法支持获取扩展信息");
        return;
    }
    my $group = shift;
    my @members = @_;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法设置管理员");
        return;
    }
    if($group->me->gtype ne "create"){
        $self->error("非群主，无法设置管理员");
        return;
    }
    for(@members){                                            
        $self->die("非群成员对象") if not $_->is_group_member;
    }
    my $ret = $self->_set_group_admin($group->gnumber,map {$_->qq} @members);
    if($ret){
        $_->role("admin") for(@members);
        $self->info("设置管理员成功");
    }
    else{$self->error("设置管理员失败")}
    return $ret;
}
sub remove_group_admin{
    my $self = shift;
    my $group = shift;
    my @members = @_;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法移除管理员");
        return;
    }
    if($group->me->gtype ne "create"){
        $self->error("非群主，无法移除管理员");
        return;
    }
    for(@members){
        $self->die("非群成员对象") if not $_->is_group_member;
    }
    my $ret = $self->_remove_group_admin($group->gnumber,map {$_->qq} @members);
    if($ret){
        $_->role("member") for(@members);
        $self->info("移除管理员成功");
    }
    else{$self->error("移除管理员失败")}
    return $ret;
}
sub set_group_member_card{
    my $self = shift;
    my $group = shift;
    my $member = shift;
    my $card = shift;
    if(not defined $group->gnumber){
        $self->error("未获取到群号码，无法设置群名片");
        return;
    }
    if(!$member->is_me and $group->me->gtype ne "manage" and $group->me->gtype ne "create"){
        $self->error("非群主或管理员，无法设置其他人群名片");
        return;
    }
    $self->die("非群成员对象") if not $member->is_group_member;
    my $ret = $self->_set_group_member_card($group->gnumber,$member->qq,$card);
    if($ret){
        $member->card($card);
        if(defined $card){$self->info("设置群名片成功");}
        else{$self->info("取消群名片成功");}
    }
    else{$self->error("设置群名片失败")}
    return $ret;
}

sub new_user{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::User->new($hash);
}
sub new_friend{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::Friend->new($hash);
}
sub new_group{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::Group->new($hash);
}
sub new_group_member{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::Group::Member->new($hash);
}
sub new_discuss{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::Discuss->new($hash);
}
sub new_discuss_member{
    my $self = shift;
    my $hash = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
    $hash->{_client} = $self;
    Mojo::Webqq::Discuss::Member->new($hash);
}

1;
