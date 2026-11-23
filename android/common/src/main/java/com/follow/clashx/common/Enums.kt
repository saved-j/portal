package com.follow.clashx.common

import com.google.gson.annotations.SerializedName

enum class QuickAction {
    STOP,
    START,
    TOGGLE,
    PING,
}

enum class BroadcastAction {
    VPN_START_REQUESTED,
    VPN_REVOKED,
    PING,
    NEXT_SERVER,
}

enum class AccessControlMode {
    @SerializedName("acceptSelected")
    ACCEPT_SELECTED,

    @SerializedName("rejectSelected")
    REJECT_SELECTED,
}
