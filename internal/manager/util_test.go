package manager

import (
	"slices"
	"testing"
)

func TestStripDirFlag(t *testing.T) {
	cases := []struct {
		in      []string
		dir     string
		wantArg []string
		wantDir string
		wantErr bool
	}{
		{[]string{"4.3"}, "", []string{"4.3"}, "", false},
		{[]string{"--dir", "/a", "4.3"}, "", []string{"4.3"}, "/a", false},
		{[]string{"4.3", "--dir=/b"}, "/a", []string{"4.3"}, "/b", false},
		{[]string{"-C", "/c", "--unset"}, "", []string{"--unset"}, "/c", false},
		{[]string{"--dir"}, "", nil, "", true},
		{[]string{"--dir="}, "", nil, "", true},
	}
	for _, c := range cases {
		args, dir, err := stripDirFlag(c.in, c.dir)
		if (err != nil) != c.wantErr {
			t.Errorf("%v: err = %v", c.in, err)
			continue
		}
		if !c.wantErr && (!slices.Equal(args, c.wantArg) || dir != c.wantDir) {
			t.Errorf("%v: got %v %q, want %v %q", c.in, args, dir, c.wantArg, c.wantDir)
		}
	}
}
