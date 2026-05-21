package terminal

import (
	"encoding/binary"
	"errors"
)

type FrameType byte

const (
	FrameData   FrameType = 0x01
	FrameResize FrameType = 0x02
	FrameClose  FrameType = 0x03
	FrameExit   FrameType = 0x04
	FrameError  FrameType = 0x05
)

func EncodeDataFrame(data []byte) []byte {
	return encodeFrame(FrameData, data)
}

func EncodeResizeFrame(cols uint16, rows uint16) []byte {
	frame := []byte{byte(FrameResize), 0, 0, 0, 0}
	binary.BigEndian.PutUint16(frame[1:3], cols)
	binary.BigEndian.PutUint16(frame[3:5], rows)
	return frame
}

func EncodeCloseFrame() []byte {
	return []byte{byte(FrameClose)}
}

func EncodeExitFrame() []byte {
	return []byte{byte(FrameExit)}
}

func EncodeErrorFrame(message string) []byte {
	return encodeFrame(FrameError, []byte(message))
}

func DecodeFrame(frame []byte) (FrameType, []byte, error) {
	if len(frame) == 0 {
		return 0, nil, errors.New("empty terminal frame")
	}
	return FrameType(frame[0]), frame[1:], nil
}

func DecodeResizeFrame(payload []byte) (uint16, uint16, error) {
	if len(payload) != 4 {
		return 0, 0, errors.New("terminal resize frame must contain cols and rows")
	}
	return binary.BigEndian.Uint16(payload[0:2]), binary.BigEndian.Uint16(payload[2:4]), nil
}

func encodeFrame(frameType FrameType, payload []byte) []byte {
	frame := make([]byte, 1+len(payload))
	frame[0] = byte(frameType)
	copy(frame[1:], payload)
	return frame
}
