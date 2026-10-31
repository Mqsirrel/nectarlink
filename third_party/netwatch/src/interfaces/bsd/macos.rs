use libc::c_int;

use super::{MessageType, RoutingStack, WireFormat};

// net/route.h constants (not exported by `libc` on iOS targets).
pub const NET_RT_DUMP: c_int = 1;
pub const NET_RT_FLAGS: c_int = 2;
pub const NET_RT_IFLIST: c_int = 3;
pub const NET_RT_IFLIST2: c_int = 6;
pub const NET_RT_DUMP2: c_int = 7;

pub const RTF_UP: c_int = 0x1;
pub const RTF_GATEWAY: c_int = 0x2;
pub const RTF_IFSCOPE: c_int = 0x1000000;

pub const RTAX_DST: c_int = 0;
pub const RTAX_GATEWAY: c_int = 1;
pub const RTAX_NETMASK: c_int = 2;
pub const RTAX_GENMASK: c_int = 3;
pub const RTAX_IFP: c_int = 4;
pub const RTAX_IFA: c_int = 5;
pub const RTAX_AUTHOR: c_int = 6;
pub const RTAX_BRD: c_int = 7;
pub const RTAX_MAX: c_int = 8;

pub const RTA_DST: c_int = 0x1;
pub const RTA_GATEWAY: c_int = 0x2;
pub const RTA_NETMASK: c_int = 0x4;
pub const RTA_GENMASK: c_int = 0x8;
pub const RTA_IFP: c_int = 0x10;
pub const RTA_IFA: c_int = 0x20;
pub const RTA_AUTHOR: c_int = 0x40;
pub const RTA_BRD: c_int = 0x80;

pub const RTM_VERSION: c_int = 5;

pub const RTM_ADD: c_int = 0x1;
pub const RTM_DELETE: c_int = 0x2;
pub const RTM_CHANGE: c_int = 0x3;
pub const RTM_GET: c_int = 0x4;
pub const RTM_LOSING: c_int = 0x5;
pub const RTM_REDIRECT: c_int = 0x6;
pub const RTM_MISS: c_int = 0x7;
pub const RTM_LOCK: c_int = 0x8;
pub const RTM_OLDADD: c_int = 0x9;
pub const RTM_OLDDEL: c_int = 0xa;
pub const RTM_RESOLVE: c_int = 0xb;
pub const RTM_NEWADDR: c_int = 0xc;
pub const RTM_DELADDR: c_int = 0xd;
pub const RTM_IFINFO: c_int = 0xe;
pub const RTM_NEWMADDR: c_int = 0xf;
pub const RTM_DELMADDR: c_int = 0x10;
pub const RTM_IFINFO2: c_int = 0x12;
pub const RTM_NEWMADDR2: c_int = 0x13;
pub const RTM_GET2: c_int = 0x14;

// Hardcoded based on the generated values here: https://cs.opensource.google/go/x/net/+/master:route/zsys_darwin.go
const SIZEOF_IF_MSGHDR_DARWIN15: usize = 0x70;
const SIZEOF_IFA_MSGHDR_DARWIN15: usize = 0x14;
const SIZEOF_IFMA_MSGHDR_DARWIN15: usize = 0x10;
const SIZEOF_IF_MSGHDR2_DARWIN15: usize = 0xa0;
const SIZEOF_IFMA_MSGHDR2_DARWIN15: usize = 0x14;
const SIZEOF_IF_DATA_DARWIN15: usize = 0x60;
const SIZEOF_IF_DATA64_DARWIN15: usize = 0x80;

const SIZEOF_RT_MSGHDR_DARWIN15: usize = 0x5c;
const SIZEOF_RT_MSGHDR2_DARWIN15: usize = 0x5c;
const SIZEOF_RT_METRICS_DARWIN15: usize = 0x38;

const SIZEOF_SOCKADDR_STORAGE: usize = 0x80;
pub(super) const SIZEOF_SOCKADDR_INET: usize = 0x10;
pub(super) const SIZEOF_SOCKADDR_INET6: usize = 0x1c;

pub(super) fn probe_routing_stack() -> RoutingStack {
    let rtm_version = RTM_VERSION;

    let rtm = WireFormat {
        ext_off: 36,
        body_off: SIZEOF_RT_MSGHDR_DARWIN15,
        typ: MessageType::Route,
    };
    let rtm2 = WireFormat {
        ext_off: 36,
        body_off: SIZEOF_RT_MSGHDR2_DARWIN15,
        typ: MessageType::Route,
    };
    let ifm = WireFormat {
        ext_off: 16,
        body_off: SIZEOF_IF_MSGHDR_DARWIN15,
        typ: MessageType::Interface,
    };
    let ifm2 = WireFormat {
        ext_off: 32,
        body_off: SIZEOF_IF_MSGHDR2_DARWIN15,
        typ: MessageType::Interface,
    };
    let ifam = WireFormat {
        ext_off: SIZEOF_IFA_MSGHDR_DARWIN15,
        body_off: SIZEOF_IFA_MSGHDR_DARWIN15,
        typ: MessageType::InterfaceAddr,
    };
    let ifmam = WireFormat {
        ext_off: SIZEOF_IFMA_MSGHDR_DARWIN15,
        body_off: SIZEOF_IFMA_MSGHDR_DARWIN15,
        typ: MessageType::InterfaceMulticastAddr,
    };
    let ifmam2 = WireFormat {
        ext_off: SIZEOF_IFMA_MSGHDR2_DARWIN15,
        body_off: SIZEOF_IFMA_MSGHDR2_DARWIN15,
        typ: MessageType::InterfaceMulticastAddr,
    };

    let wire_formats = [
        (RTM_ADD, rtm),
        (RTM_DELETE, rtm),
        (RTM_CHANGE, rtm),
        (RTM_GET, rtm),
        (RTM_LOSING, rtm),
        (RTM_REDIRECT, rtm),
        (RTM_MISS, rtm),
        (RTM_LOCK, rtm),
        (RTM_RESOLVE, rtm),
        (RTM_NEWADDR, ifam),
        (RTM_DELADDR, ifam),
        (RTM_IFINFO, ifm),
        (RTM_NEWMADDR, ifmam),
        (RTM_DELMADDR, ifmam),
        (RTM_IFINFO2, ifm2),
        (RTM_NEWMADDR2, ifmam2),
        (RTM_GET2, rtm2),
    ]
    .into_iter()
    .collect();

    RoutingStack {
        rtm_version,
        wire_formats,
        kernel_align: 4,
    }
}
