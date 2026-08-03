package rikka.shizuku

import android.os.IBinder
import android.os.Parcel
import android.os.Parcelable

/** Legacy wire type emitted by the installed ShizukuPlus server. */
class BinderContainer(val binder: IBinder) : Parcelable {
    private constructor(source: Parcel) : this(source.readStrongBinder())

    override fun describeContents() = 0
    override fun writeToParcel(destination: Parcel, flags: Int) = destination.writeStrongBinder(binder)

    companion object CREATOR : Parcelable.Creator<BinderContainer> {
        override fun createFromParcel(source: Parcel) = BinderContainer(source)
        override fun newArray(size: Int) = arrayOfNulls<BinderContainer>(size)
    }
}
