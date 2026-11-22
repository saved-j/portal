package com.follow.clashx.service.models

data class NotificationParams(
    val title: String = "FlClashX",
    val server: String = "",
    val stopText: String = "STOP",
    val showStopAction: Boolean = true,
    val pingText: String = "PING",
    val showPing: Boolean = false,
    val detail: String = "",
)
