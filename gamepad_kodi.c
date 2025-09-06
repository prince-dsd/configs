#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#define die(msg) \
do { perror(msg); exit(EXIT_FAILURE); } while (0)

    // Adjust this to your real gamepad's device path
    #define REAL_DEVICE "/dev/input/event13"  // Change to match your real controller

    int setup_uinput_device(int *uinput_fd) {
        struct uinput_user_dev uidev;
        int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
        if (fd < 0) die("open /dev/uinput");

        // Enable key and ABS (axis) events
        ioctl(fd, UI_SET_EVBIT, EV_KEY);
        ioctl(fd, UI_SET_EVBIT, EV_ABS);

        // Common buttons
        ioctl(fd, UI_SET_KEYBIT, BTN_A);
        ioctl(fd, UI_SET_KEYBIT, BTN_B);
        ioctl(fd, UI_SET_KEYBIT, BTN_X);
        ioctl(fd, UI_SET_KEYBIT, BTN_Y);
        ioctl(fd, UI_SET_KEYBIT, BTN_START);
        ioctl(fd, UI_SET_KEYBIT, BTN_SELECT);
        ioctl(fd, UI_SET_KEYBIT, BTN_TL);
        ioctl(fd, UI_SET_KEYBIT, BTN_TR);
        ioctl(fd, UI_SET_KEYBIT, BTN_THUMBL);
        ioctl(fd, UI_SET_KEYBIT, BTN_THUMBR);
        ioctl(fd, UI_SET_KEYBIT, BTN_DPAD_UP);
        ioctl(fd, UI_SET_KEYBIT, BTN_DPAD_DOWN);
        ioctl(fd, UI_SET_KEYBIT, BTN_DPAD_LEFT);
        ioctl(fd, UI_SET_KEYBIT, BTN_DPAD_RIGHT);

        // Axes
        ioctl(fd, UI_SET_ABSBIT, ABS_X);
        ioctl(fd, UI_SET_ABSBIT, ABS_Y);
        ioctl(fd, UI_SET_ABSBIT, ABS_RX);
        ioctl(fd, UI_SET_ABSBIT, ABS_RY);
        ioctl(fd, UI_SET_ABSBIT, ABS_Z);
        ioctl(fd, UI_SET_ABSBIT, ABS_RZ);
        ioctl(fd, UI_SET_ABSBIT, ABS_HAT0X);
        ioctl(fd, UI_SET_ABSBIT, ABS_HAT0Y);

        memset(&uidev, 0, sizeof(uidev));
        snprintf(uidev.name, UINPUT_MAX_NAME_SIZE, "Virtual Passthrough Gamepad");
        uidev.id.bustype = BUS_USB;
        uidev.id.vendor = 0x1234;
        uidev.id.product = 0x5678;
        uidev.id.version = 1;

        // Set axis ranges
        uidev.absmin[ABS_X] = -32768;
        uidev.absmax[ABS_X] = 32767;
        uidev.absmin[ABS_Y] = -32768;
        uidev.absmax[ABS_Y] = 32767;
        uidev.absmin[ABS_RX] = -32768;
        uidev.absmax[ABS_RX] = 32767;
        uidev.absmin[ABS_RY] = -32768;
        uidev.absmax[ABS_RY] = 32767;
        uidev.absmin[ABS_Z] = 0;
        uidev.absmax[ABS_Z] = 255;
        uidev.absmin[ABS_RZ] = 0;
        uidev.absmax[ABS_RZ] = 255;
        uidev.absmin[ABS_HAT0X] = -1;
        uidev.absmax[ABS_HAT0X] = 1;
        uidev.absmin[ABS_HAT0Y] = -1;
        uidev.absmax[ABS_HAT0Y] = 1;

        if (write(fd, &uidev, sizeof(uidev)) < 0) die("write uidev");
        if (ioctl(fd, UI_DEV_CREATE) < 0) die("UI_DEV_CREATE");

        *uinput_fd = fd;
        return 0;
    }

    void emit_event(int fd, int type, int code, int value) {
        struct input_event ev;
        memset(&ev, 0, sizeof(ev));
        gettimeofday(&ev.time, NULL);
        ev.type = type;
        ev.code = code;
        ev.value = value;
        if (write(fd, &ev, sizeof(ev)) < 0)
            perror("write event");
    }

    int main() {
        int real_fd = open(REAL_DEVICE, O_RDONLY);
        if (real_fd < 0) die("open real gamepad");

        int virt_fd;
        setup_uinput_device(&virt_fd);

        struct input_event ev;
        printf("✅ Passthrough started. Forwarding input from %s\n", REAL_DEVICE);

        while (1) {
            ssize_t n = read(real_fd, &ev, sizeof(ev));
            if (n != sizeof(ev)) continue;

            // Only forward key/abs events to virtual device
            if (ev.type == EV_KEY || ev.type == EV_ABS) {
                emit_event(virt_fd, ev.type, ev.code, ev.value);
            }

            if (ev.type == EV_SYN) {
                emit_event(virt_fd, EV_SYN, SYN_REPORT, 0);
            }
        }

        ioctl(virt_fd, UI_DEV_DESTROY);
        close(virt_fd);
        close(real_fd);
        return 0;
    }
