package terminal

import "testing"

func TestTerminalBinaryDataFrame(t *testing.T) {
	frame := EncodeDataFrame([]byte("hello"))
	frameType, payload, err := DecodeFrame(frame)
	if err != nil {
		t.Fatal(err)
	}
	if frameType != FrameData || string(payload) != "hello" {
		t.Fatalf("frameType=%v payload=%q, want data hello", frameType, payload)
	}
}

func TestTerminalBinaryResizeFrame(t *testing.T) {
	frame := EncodeResizeFrame(132, 43)
	frameType, payload, err := DecodeFrame(frame)
	if err != nil {
		t.Fatal(err)
	}
	cols, rows, err := DecodeResizeFrame(payload)
	if err != nil {
		t.Fatal(err)
	}
	if frameType != FrameResize || cols != 132 || rows != 43 {
		t.Fatalf("frameType=%v cols=%d rows=%d, want resize 132x43", frameType, cols, rows)
	}
}

func TestTerminalBinaryResizeFrameRejectsInvalidPayload(t *testing.T) {
	if _, _, err := DecodeResizeFrame([]byte{1, 2, 3}); err == nil {
		t.Fatal("expected invalid resize payload to fail")
	}
}
