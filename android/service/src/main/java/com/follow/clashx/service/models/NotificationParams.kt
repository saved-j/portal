package com.follow.clashx.service.models

data class NotificationParams(
    val title: String = "FlClashX",
    val server: String = "",
    val stopText: String = "STOP",
    val showStopAction: Boolean = true,
    val pingText: String = "PING",
    val showPing: Boolean = false,
    /// True in the simple portal: the shade's button cycles the xray node instead of pinging.
    val nextAction: Boolean = false,
    val latency: String = "",
    val detail: String = "",
    val stats: String = "",
)
