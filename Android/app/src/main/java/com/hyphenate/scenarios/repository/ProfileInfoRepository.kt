package com.hyphenate.scenarios.repository

import com.hyphenate.EMCallBack
import com.hyphenate.EMValueCallBack
import com.hyphenate.chat.EMUserInfo
import com.hyphenate.cloud.HttpCallback
import com.hyphenate.cloud.HttpClientManager
import com.hyphenate.easeui.EaseIM
import com.hyphenate.easeui.common.ChatClient
import com.hyphenate.easeui.common.ChatError
import com.hyphenate.easeui.common.ChatException
import com.hyphenate.easeui.common.ChatHttpClientManagerBuilder
import com.hyphenate.easeui.common.ChatLog
import com.hyphenate.easeui.common.ChatUserInfo
import com.hyphenate.easeui.common.ChatUserInfoType
import com.hyphenate.easeui.common.ChatValueCallback
import com.hyphenate.easeui.model.EaseProfile
import com.hyphenate.scenarios.BuildConfig
import com.hyphenate.scenarios.DemoHelper
import com.hyphenate.scenarios.bean.MatchUserInfo
import com.hyphenate.scenarios.bean.RtcTokenResult
import com.hyphenate.scenarios.common.suspend.fetUserInfo
import com.hyphenate.scenarios.common.suspend.updateOwnAttribute
import com.hyphenate.util.EMLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class ProfileInfoRepository: BaseRepository()  {

    companion object {
        private const val UPLOAD_AVATAR_URL = BuildConfig.APP_SERVER_PROTOCOL + "://" + BuildConfig.APP_SERVER_DOMAIN +
                BuildConfig.APP_BASE_USER
        private const val SYNC_RTC_TOKEN = BuildConfig.APP_SERVER_PROTOCOL + "://" + BuildConfig.APP_SERVER_DOMAIN +
                BuildConfig.APP_RTC_TOKEN_URL

    }

    suspend fun getUserInfoAttribute(userIds: List<String>, attributes: List<ChatUserInfoType>): Map<String, ChatUserInfo> =
        withContext(Dispatchers.IO) {
            ChatClient.getInstance().userInfoManager().fetUserInfo(userIds,attributes)
        }

    suspend fun synchronizeProfile(isSyncFromServer:Boolean):EaseProfile? =
        withContext(Dispatchers.IO) {
            val currentProfile = EaseIM.getCurrentUser()?:EaseProfile(ChatClient.getInstance().currentUser)
            val user = DemoHelper.getInstance().dataModel.getUser(currentProfile.id)
            ChatLog.e("ProfileInfoRepository","synchronizeProfile $user $isSyncFromServer - $currentProfile")
            suspendCoroutine { continuation ->
                if (user == null || isSyncFromServer){
                    currentProfile.let { profile->
                        val ids = mutableListOf(profile.id)
                        val type = mutableListOf(ChatUserInfoType.NICKNAME,ChatUserInfoType.AVATAR_URL)
                        ChatClient.getInstance().userInfoManager().fetchUserInfoByAttribute(ids.toTypedArray(),type.toTypedArray(),object :
                            EMValueCallBack<MutableMap<String, EMUserInfo>>{
                            override fun onSuccess(value: MutableMap<String, EMUserInfo>?) {
                                ChatLog.e("ProfileInfoRepository","fetchUserInfoByAttribute onSuccess ${profile.id} - $value")
                                value?.let { map->
                                    if (value.containsKey(profile.id)){
                                        map[profile.id]?.let {
                                            profile.name = it.nickname
                                            profile.avatar = it.avatarUrl
                                            EaseIM.updateUsersInfo(mutableListOf(profile))
                                            continuation.resume(profile)
                                        }
                                    }
                                }
                            }

                            override fun onError(error: Int, errorMsg: String?) {
                                ChatLog.e("ProfileInfoRepository","fetchUserInfoByAttribute onError$error $errorMsg")
                                continuation.resumeWithException(ChatException(error, errorMsg))
                            }
                        })
                    }
                }else{
                    ChatLog.e("ProfileInfoRepository","fetchLocalUserInfo")
                    currentProfile.let {
                        it.name = user.name
                        it.avatar = user.avatar
                        EaseIM.updateUsersInfo(mutableListOf(it))
                    }
                    continuation.resume(currentProfile)
                }
            }
        }

    suspend fun synchronizeRtcToken(channel:String,phone:String): RtcTokenResult =
        withContext(Dispatchers.IO){
            suspendCoroutine { continuation ->
                syncTokenFromServer(channel,phone,object : ChatValueCallback<RtcTokenResult>{
                    override fun onSuccess(result: RtcTokenResult) {
                        continuation.resume(result)
                    }

                    override fun onError(code: Int, error: String?) {
                        continuation.resumeWithException(ChatException(code,error))
                    }
                })
            }
        }

    suspend fun setUserRemark(username:String,remark:String): Int =
        withContext(Dispatchers.IO) {
            suspendCoroutine { continuation ->
                ChatClient.getInstance().contactManager().asyncSetContactRemark(username,remark,object :
                    EMCallBack{
                    override fun onSuccess() {
                        continuation.resume(ChatError.EM_NO_ERROR)
                    }

                    override fun onError(code: Int, error: String?) {
                        continuation.resumeWithException(ChatException(code, error))
                    }
                })
            }
        }

    /**
     * Update the nickname of the current user to chat server.
     * @param nickname The new nickname.
     */
    suspend fun updateNickname(nickname: String) =
        withContext(Dispatchers.IO) {
            ChatClient.getInstance().userInfoManager().updateOwnAttribute(ChatUserInfoType.NICKNAME, nickname)
        }

    /**
     * Upload avatar url to chat server.
     * @param remoteUrl The remote url of the avatar
     */
    suspend fun uploadAvatarToChatServer(remoteUrl: String) =
        withContext(Dispatchers.IO) {
            ChatClient.getInstance().userInfoManager().updateOwnAttribute(ChatUserInfoType.AVATAR_URL, remoteUrl)
        }

    /**
     * 上传头像
     * @return
     */
    suspend fun uploadAvatar(filePath: String?): String =
        withContext(Dispatchers.IO) {
            suspendCoroutine { continuation ->
                uploadAvatarToAppServer(filePath,object : ChatValueCallback<String>{
                    override fun onSuccess(value: String?) {
                        value?.let {
                            continuation.resume(it)
                        }
                    }

                    override fun onError(error: Int, errorMsg: String?) {
                        continuation.resumeWithException(ChatException(error, errorMsg))
                    }
                })
            }
        }

    private fun uploadAvatarToAppServer(
        filePath: String?,
        callBack: ChatValueCallback<String>
    ){
        try {
            ChatLog.e("ProfileInfoRepository","uploadAvatarToAppServer $filePath")
            if (filePath.isNullOrEmpty()){
                callBack.onError(ChatError.INVALID_URL," invalid url.")
                return
            }
            ChatLog.e("ProfileInfoRepository","uploadAvatarToAppServer ${UPLOAD_AVATAR_URL +"/${DemoHelper.getInstance().dataModel.getPhoneNumber()}"+BuildConfig.APP_UPLOAD_AVATAR}")
            ChatHttpClientManagerBuilder()
                .uploadFile(filePath)
                .setParam("file",filePath)
                .setUrl(UPLOAD_AVATAR_URL +"/${DemoHelper.getInstance().dataModel.getPhoneNumber()}"+BuildConfig.APP_UPLOAD_AVATAR)
                .execute(object : HttpCallback{
                    override fun onSuccess(result: String?) {
                        result?.let {
                            val url = try {
                            val jsonObject = JSONObject(it)
                            jsonObject.getString("avatarUrl")
                        } catch (e: Exception) {
                            e.printStackTrace()
                            ""
                        }
                            callBack.onSuccess(url)
                        } ?: callBack.onError(ChatError.NETWORK_ERROR,"result url is null.")
                    }

                    override fun onError(code: Int, msg: String?) {
                        callBack.onError(code,msg)
                    }

                    override fun onProgress(total: Long, pos: Long) {

                    }
                })
        } catch (e: Exception) {
            callBack.onError(ChatError.NETWORK_ERROR, e.message)
        }
    }

    private fun syncTokenFromServer(
        channel: String,
        phone: String?,
        callBack: ChatValueCallback<RtcTokenResult>
    ){
        val url ="${SYNC_RTC_TOKEN}/${channel}/phoneNumber/${phone}/1v1video"
        try {
            ChatLog.e("ProfileInfoRepository","syncTokenFromServer $url")
            val headers: MutableMap<String, String> = HashMap()
            headers["Content-Type"] = "application/json"
            val response = HttpClientManager.httpExecute(
                url,
                headers, "",
                HttpClientManager.Method_GET
            )
            val code = response.code
            val responseInfo = response.content
            val info = JSONObject(responseInfo)
            val result = RtcTokenResult()
            if (code == 200) {
                EMLog.d("syncTokenFromServer success : ", responseInfo)
                if (info.has("accessToken")){
                    val token = info.getString("accessToken")
                    result.accessToken = token
                }
                if (info.has("agoraUid")){
                    val agoraUid = info.getString("agoraUid")
                    result.agoraUid = agoraUid
                }
                if (info.has("expireTimestamp")){
                    val agoraUid = info.getLong("expireTimestamp")
                    result.expireTimestamp = agoraUid
                }
                callBack.onSuccess(result)
            }else{
                callBack.onError(code, info.getString("errorInfo"))
            }
        } catch (e: Exception) {
            callBack.onError(ChatError.NETWORK_ERROR, e.message)
        }
    }


}