// Original arithmetic pixel patterns; regenerate and verify every JPEG byte with
// python tools/fixtures/jpeg_provenance.py. No external image or user data.

///|
fn jpeg_sample_fixture(name : String) -> Bytes raise {
  @base64.decode(
    match name {
      "rgb444" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wAARCAANABEDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwTwx8Mvufuf0rsynMNtTxsHnO2p65pfw6+zWTOIsMRtXscn0/n+FfYZ3xJ/ZGRV68ZWm1yx97lfNLS8XveKblZa+69t195lebe0qxVy1/wrL/AKY/pX8yf2h5n6B/bPmeo+GPCNj8nH6V9ZlOKnofxBg8fV0On8eSWXgTwZPrf2Iagtq0bGDzPKL7pEj+9g4x5meh6U+L6tfMZ4DK1JRjVlOTdrtOEdOq0fM7/L5/sXBNGrnOZQwnPyc19bXtZOW112tueT/8NEWP/Qnf+VT/AO015P8AqXP/AKCf/JP/ALY/oT/UCr/0F/8Akn/25//Z"
      "rgb422" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wAARCAANABEDASEAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwTwx8Mvufuf0r1zS/h19msmcRYYjavY5Pp/P8K+ky7OvqOV18RezhCTWttUnbXo29vM1yPN+acVfsWv8AhWX/AEx/Siv58/tDzP17+2fM9R8MeEbH5OP0rp/Hkll4E8GT639iGoLatGxg8zyi+6RI/vYOMeZnoelfW1a9WrkdSlF253CF97c84xbtpsn3P5Q4Oq1cfmWHwvNbnlGN97Xdr262PJ/+GiLH/oTv/Kp/9poryf8AUuf/AEE/+Sf/AGx/W3+oFX/oL/8AJP8A7c//2Q=="
      "rgb420" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wAARCAANABEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwTwx8Mvufuf0r1zS/h19msmcRYYjavY5Pp/P8K9b8MeEbH5OP0rp/Hkll4E8GT639iGoLatGxg8zyi+6RI/vYOMeZnoelYUeJsRg8nq1KHxtKMf8AFNqEd9N5LfTufOcM8R4jG4ulh6SvKbSS7t7LU8H/AOFZf9Mf0oroP+GiLH/oTv8Ayqf/AGmivzP+z89/58/+TR/+SP6J+q8S/wDPj/yaH/yR/9k="
      "rgb_progressive" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wgARCAANABEDASIAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABgAF/8QAFwEAAwEAAAAAAAAAAAAAAAAAAwUGB//aAAwDAQACEAMQAAABArl2mNaDtCmdF//EABwQAAMAAQUAAAAAAAAAAAAAAAACBAUBAxIVFv/aAAgBAQABBQKbGG1juKdYTSIX6pDH6JD/xAAdEQABBAIDAAAAAAAAAAAAAAADAAECBRMxUqHR/9oACAEDAQE/AayxIYsRx26xWXDtvV//xAAhEQABAgQHAAAAAAAAAAAAAAABAAIDBAUxFCFScaGx0f/aAAgBAgEBPwFlTiQZNzmXsNzkO1h57RyPV//EACEQAAECBAcAAAAAAAAAAAAAAAARMQEDEBITITRBo8Hh/9oACAEBAAY/AmGGpGdZiWpkqbp2aPl8P//EABoQAAIDAQEAAAAAAAAAAAAAAAExABARIUH/2gAIAQEAAT8hVOgWQp55weGXs0Gon//aAAwDAQACAAMAAAAQ3+//xAAZEQEAAgMAAAAAAAAAAAAAAAABEBEhMVH/2gAIAQMBAT8QF21AOrozDX//xAAZEQADAAMAAAAAAAAAAAAAAAABITEQUXH/2gAIAQIBAT8QoLA6IsqFW8If/8QAIBAAAgEDBAMAAAAAAAAAAAAAAREAITFREEGBobHw8f/aAAgBAQABPxD50TqkMBZx54nsptPUR+QK3EhSqsbaE//Z"
      "rgb_progressive444" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wgARCAANABEDAREAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABgMF/8QAGQEAAgMBAAAAAAAAAAAAAAAABQcBBAYD/9oADAMBAAIQAxAAAAED2pLjB6qx0CkskNOdiTqML//EABwQAAMAAQUAAAAAAAAAAAAAAAACBAUBAxIVFv/aAAgBAQABBQKbGG1juKdYTSIX6pDH6JD/xAAhEQABAwIHAQAAAAAAAAAAAAAAAgMEAREFEhQVU6Hh8f/aAAgBAwEBPwFmYRZeZVDWDL6jBEKmSaNXtf6bArl69P/EACURAAEDAQYHAAAAAAAAAAAAAAEAAgQRAwUUITHhFVFTcYGRof/aAAgBAgEBPwGJIU28sJBe8HPQZ0zPLtr4WIUS1Kvdz5BsItaBxJ9DdcFPU+br/8QAIRAAAQIEBwAAAAAAAAAAAAAAABExAQMQEhMhNEGjweH/2gAIAQEABj8CYYakZ1mJamSpunZo+Xw//8QAGhAAAgMBAQAAAAAAAAAAAAAAATEAEBEhQf/aAAgBAQABPyFU6BZCnnnB4ZezQaif/9oADAMBAAIAAwAAABC3qT//xAAcEQABBAMBAAAAAAAAAAAAAAARAAEhMRBBUXH/2gAIAQMBAT8QplARXtQ1s3pBAZ6FuC8f/8QAGxEBAAIDAQEAAAAAAAAAAAAAAREhADFBgXH/2gAIAQIBAT8Q0XlXjOholbkLAu2tn1lHD8EpiUaulMp89x3/xAAgEAACAQMEAwAAAAAAAAAAAAABEQAhMVEQQYGhsfDx/9oACAEBAAE/EPnROqQwFnHnieym09RH5ArcSFKqxtoT/9k="
      "rgb_restart" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wAARCAANABEDAREAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/90ABAAB/9oADAMBAAIRAxEAPwDwTwx8Mvufuf0rsynMNtTxsHnO2p//0MDS/h19msmcRYYjavY5Pp/P8K+8zviT+yMir14ytNrlj73K+aWl4ve8U3Ky1917br6PK829pVirn//Ryv8AhWX/AEx/SvyD+0PM/Y/7Z8z/0u88MeEbH5OP0r4zKcVPQ/A8Hj6uh//T9j8eSWXgTwZPrf2Iagtq0bGDzPKL7pEj+9g4x5meh6V8bxfVr5jPAZWpKMaspybtdpwjp1Wj5nf5fPxeCaNXOcyhhOfk5r62vayctrrtbc//1Lf/AA0RY/8AQnf+VT/7TX5v/qXP/oJ/8k/+2P2r/UCr/wBBf/kn/wBuf//Z"
      "rgb_progressive_restart" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQFBQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhr/wgARCAANABEDAREAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAwUGBP/EABcBAQEBAQAAAAAAAAAAAAAAAAYFBAP/3QAEAAH/2gAMAwEAAhADEAAAAYHti//QX3qP/9HIPY//0n0UD//TsY2L/9Qptr//xAAcEAADAAEFAAAAAAAAAAAAAAAAAgQFAQMSFRb/2gAIAQEAAQUCmxh//9Dax3FP/9HrD//SmkQ//9O/VIY//9T0SH//xAAhEQABAwIHAQAAAAAAAAAAAAAAAgMEAREFEhQVU6Hh8f/aAAgBAwEBPwFmYf/Qiy8yqH//0dYf/9Jl9R//08EQqZJo1e1/p//U2BXL16f/xAAlEQABAwEGBwAAAAAAAAAAAAABAAIEEQMFFCEx4RVRU3GBkaH/2gAIAQIBAT8BiSF//9CbeWEgveDnoM6Znl218L//0cQv/9KJalf/073c+QbCLWgcSfQ3X//U4Kep83X/xAAgEAACAQEJAAAAAAAAAAAAAAAAETESAQMTITRBo8Hh/9oACAEBAAY/AoP/0IP/0YP/0j//07b6jEpWTW67P//U0fL4f//EABkQAAMBAQEAAAAAAAAAAAAAAAABMREhQf/aAAgBAQABPyGR/9DQdRH/0R//0uc//9Pg8dvZqUP/1BP/2gAMAwEAAgADAAAAEL//0L//0f8A/9Jf/9Of/9Sf/8QAGxEAAgMAAwAAAAAAAAAAAAAAABEBITFBUXH/2gAIAQMBAT8Qxs//0EJn/9H2f//Spn//0+TetNKJw46Wn//UP//EABsRAQACAwEBAAAAAAAAAAAAAAERIQAxQYFx/9oACAECAQE/ENF5/9CrxnQ0StyFgXbWz//R+s//0qOf/9M/BKYlGrpTKfPf/9THf//EAB8QAAIBAwUBAAAAAAAAAAAAAAERACExUUGBobHw8f/aAAgBAQABPxD50//QTqkMBZx3tP/R9Kf/0tJ4n//TR+QK3EhSqsbT/9SE/9k="
      "rgb_direct" =>
        "/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAEAwMEAwMEBAMEBQQEBQYKBwYGBgYNCQoICg8NEBAPDQ8OERMYFBESFxIODxUcFRcZGRsbGxAUHR8dGh8YGhsa/8AAEQgADQARA1IRAEcRAEIRAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/aAAwDUgBHAEIAAD8A+Yfh5pv+q49K8Ss/gZ0/0b/x2vGfgxoP/Hv8vpX1h8PNN/1XHpXQWfwM6f6N/wCO19YeO/E3/CsfgZ4m1i3m+z6ncWn9naaUvPss32i4/dh4mHzGSNWeYBecRHlcFh7H/ZvtWl/woz/p2/8AHa/Pj+wf9mvhf4eWifuvwr7is/h1pXHy/wDjtfT/AMGNNh/0f8O1fWPw8tE/dfhXP/GG40r4OfDDXPG39k/21/ZX2f8A0Lz/ALP5vm3EcP8ArNrYx5mfunOMcZzXU/ti6lLa+Ffhx4cjjhNjqOoXV/K5U+YslvGkaBTnG0i7kzkE5C4Iwc+x/ZEr5Q/4bw0r/oln/lxf/c1fP/8AZsP+RX//2Q=="
      "gray" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/wAALCAANABEBAREA/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oACAEBAAA/APBPDHwy+5+5/SvXNL+HX2ayZxFhiNq9jk+n8/wq1/wrL/pj+leo+GPCNj8nH6V0/jySy8CeDJ9b+xDUFtWjYweZ5RfdIkf3sHGPMz0PSvJ/+GiLH/oTv/Kp/wDaa//Z"
      "gray_progressive" =>
        "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0JCggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/wgALCAANABEBAREA/8QAFgABAQEAAAAAAAAAAAAAAAAABgMF/9oACAEBAAAAAQK6qnTJ/wD/xAAcEAADAAEFAAAAAAAAAAAAAAAAAgQFAQMSFRb/2gAIAQEAAQUCmxhtY7inWE0iF+qQx+iQ/8QAIRAAAQIEBwAAAAAAAAAAAAAAABExAQMQEhMhNEGjweH/2gAIAQEABj8CYYakZ1mJamSpunZo+Xw//8QAGhAAAgMBAQAAAAAAAAAAAAAAATEAEBEhQf/aAAgBAQABPyFU6BZCnnnB4ZezQaif/9oACAEBAAAAEO//xAAgEAACAQMEAwAAAAAAAAAAAAABEQAhMVEQQYGhsfDx/9oACAEBAAE/EPnROqQwFnHnieym09RH5ArcSFKqxtoT/9k="
      "cmyk" =>
        "/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAEAwMEAwMEBAMEBQQEBQYKBwYGBgYNCQoICg8NEBAPDQ8OERMYFBESFxIODxUcFRcZGRsbGxAUHR8dGh8YGhsa/8AAFAgADQARBEMRAE0RAFkRAEsRAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/aAA4EQwBNAFkASwAAPwD5h+Hmm/6rj0rxKz+BnT/Rv/Ha8Z+DGg/8e/y+lff1fWHw803/AFXHpXQWfwM6f6N/47X1h478Tf8ACsfgZ4m1i3m+z6ncWn9naaUvPss32i4/dh4mHzGSNWeYBecRHlcFgV7H/ZvtWl/woz/p2/8AHa/Pj+wf9mivhf4eWifuvwr7is/h1pXHy/8AjtfT/wAGNNh/0f8ADtRX1j8PLRP3X4Vz/wAYbjSvg58MNc8bf2T/AG1/ZX2f/QvP+z+b5txHD/rNrYx5mfunOMcZzXU/ti6lLa+Ffhx4cjjhNjqOoXV/K5U+YslvGkaBTnG0i7kzkE5C4Iwclex/ZEr5Q/4bw0r/AKJZ/wCXF/8Ac1fP/wDZsP8AkUV//9k="
      "cmyk_progressive" =>
        "/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAEAwMEAwMEBAMEBQQEBQYKBwYGBgYNCQoICg8NEBAPDQ8OERMYFBESFxIODxUcFRcZGRsbGxAUHR8dGh8YGhsa/8IAFAgADQARBEMRAE0RAFkRAEsRAP/EABkAAQADAQEAAAAAAAAAAAAAAAcABQYECP/aAA4EQwBNAFkASwAAAAEwxGMf1iwWJsenz3AtxUIs19pNiUH8/8QAGRAAAgMBAAAAAAAAAAAAAAAAAAUCAxIT/9oACAFDAAEFAl9YvrOYviL4mT//xAAZEAADAQEBAAAAAAAAAAAAAAAAAgUDFRb/2gAIAU0AAQUCSGJDOGJOyLDZR5nvMj//xAAcEAABBAMBAAAAAAAAAAAAAAAAAQMEBQIGExX/2gAIAVkAAQUCpmCdJ8yj4FM2huLi4xeaH//EABQQAQAAAAAAAAAAAAAAAAAAACD/2gAIAUsAAQUCX//EABYQAQEBAAAAAAAAAAAAAAAAAAEAEP/aAAgBQwAGPwIjCM//xAAjEAAABAMJAAAAAAAAAAAAAAAAERMyAQISAwQQIjE1gaTi/9oACAFNAAY/Amhobhb31JZKnIdJnNCGvI2vseR//8QAJBAAAgEBBgcAAAAAAAAAAAAAAQIDEgAEBRARIRMiMVFhgcL/2gAIAVkABj8CW15mU0yMvDj56TU223kdfWS2w67gCiSRnPfVRp9HL//EABQQAQAAAAAAAAAAAAAAAAAAACD/2gAIAUsABj8CX//EABcQAQEBAQAAAAAAAAAAAAAAAAABEBH/2gAIAUMAAT8h3bMmcv/EABsQAAICAwEAAAAAAAAAAAAAAAABofAQEVHh/9oACAFNAAE/IakVIto4IPBuIJwwb//EAB8QAAEDAwUAAAAAAAAAAAAAAAEAEBEhMVFBYXGRwf/aAAgBWQABPyHGWnyrlgrwE09Lri3SvM0UABG3k3//xAAUEAEAAAAAAAAAAAAAAAAAAAAg/9oACAFLAAE/IV//2gAOBEMATQBZAEsAAAAQROxq/8QAGBAAAwEBAAAAAAAAAAAAAAAAAFGhEHH/2gAIAUMAAT8QVQqjgnk/P//EABkQAAIDAQAAAAAAAAAAAAAAABEhABAx8f/aAAgBTQABPxDGWNWThy4WwA2iAiab/8QAGxABAQACAwEAAAAAAAAAAAAAAREAITFBofD/2gAIAVkAAT8Q8jOZBbqAbYCNo9wjDyOsaYU6gKrKLUWkJG/Ez//EABQQAQAAAAAAAAAAAAAAAAAAACD/2gAIAUsAAT8QX//Z"
      _ => fail("unknown JPEG fixture")
    },
  )
}

// Generated fixtures: deterministic Pillow/libjpeg-turbo patterns, quality 87.
// Oracle: PDF.js 6.4.299 JpegImage.getData(), forceRGB=false.
// No external files or runtimes required by these all-target tests.

///|
test "JPEG rgb444 sample oracle" {
  let bytes = jpeg_sample_fixture("rgb444")
  let expected = @base64.decode(
    "AAACCgIRFwQkIgY2KghENQtVQg1pTA14WRCVXw6PdRa4fBy+dBDKkibSnxjxrxT/ryAQAhIHDhMWHBUpJxc7LRpIOR1aRx5tUh98XyWVZiWNcyihfCnDgyjnkTDYoyrpoD4AszIVBicKECgYHikrKSw9Mi9MPDBeSTNzVDSAXjaZajinczexfTy6jknYkzvxrUD1nUUXt0cZCToPEjsdIT0xKz5CNEFRPURhTEZ2VkaEXkiRb06peUfagFC+jVPmlU/lrEn8q10SuVkdDE0XFk0lJU85MFFKN1RYQVZpUFh9W1mLZGCVcV+zgGLGhGHViWDWoF//o3gAsG0FvGwlDl8aGmAqKGE+MGROOWddRGpvUmuCXWuQZ3Cpb260fXeliXTpknblqnn3oYEAs3cXv34qEXUfG3UtKXZANXlSPHtgRn5xVH+GYICVZ4aYcoDLfYmzjYzYmo/4o4D/qo4qvY0hw5MtFoYkIIYyLYhFOItXQY1mS492WpGLY5KYa5K7e56yhJfRjZjom5/okKoAraIVxaAbxqUyF5ooIpo2L5xJOp9dQ6JsTaN8W6aRZaaea6zAerKvhajOlKvhprPqproNqbQay7Ihx7k2G6ouJqo8NK1QPq5iR7FxUrSDX7aWabakf7W/eMLFkbzcl8T7qLn/q7oVrdARwL8pyctDHr8zKb9CN8BWQsNnScd2VMiHY8qbbcupicS+ctTIksvold7nqdTkttUNvectx9gyz91AIdI5K9RHOtZbRNdsTdp6V9yLZN+gb9+tdOC+eOrimurPneTmmfUKovUAsN4jyPo51PFJI+I8L+RKPeVeSOdwTup9WeyRZ+2kc++zifXBjvXKh+/umvT0p/8Jvu8awQs+0wAz0AJK",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb422 sample oracle" {
  let bytes = jpeg_sample_fixture("rgb422")
  let expected = @base64.decode(
    "AAAHAwYNHgIYJQkfLgJbNQliPw9lRBRqXg2WXg2WcxmveR+1eBG7jyjSpRL/qhf/ryAQARMHBxkNIRAwKBc3MhdOOR5VRCBqSiZwYyGcZCKdcyWteiy0hyrRjjHYqTqJmSp5szIVBSgKCi0PJSBILCdPNCtWOjFcRzVvTDp0YzOZajqgdDazez26lEH1kD3xsVOHljhst0cZBzgYDD0dKDc+Lj1ENz5bPURhSUh0Tk15ZEGlb0ywe0rKf07OklDlklDlsF+CoVBzuVkdDEolEU8qK1AlMVYrO1RRQVpXTFmDUV6Ia1ewcl63g1zZhl/ckl7MnWnXpnIPpXEOvGwlDl4jFGQpL2EsNWcyPGVfQ2xmTmqRU2+WbnCZcHKbgmzQjHbamm77pXn/pH8Ap4IAv34qEnIqF3cvMHNAN3pHP3V1Rnx8UICMVoaSboKac4efhIHIj4zTpYvuoIbpq40rr5Evw5MtF4A+HIVDNIVCO4xJRIl0So96VpZ8W5uBc4zEfpfPi5PRkZnXpq5/jZVmrqIOtakVxqUyGZgvHp00QZFUSJhbSJ5tTqRzXKGpYaaugqK3iKi9hqu+jrPGpMKgj62LsbAau7okx7k2D681FLQ6OKtQPrFWTq1zVbR6WLifXb2kbcGyc8e4jL/clsnmuMiZna1+yMEYxr8WyctDG788IMRBNMNRO8pYUMJ9VsiDYMyYZdGddtGyedS1msbtptL5s+R5n9Blse8irOodz91AJs9CK9RHOtRmQNpsUtGcWNeiZNuxaeC2gNfPi+LaoeHtoeHtm/IXm/IXv9oT2fQt1PFJIOJDJuhJPuRgRetnVehzXO96XvmBZP+HgvfKhPnMhPTejf3ns/owrfQqwApDvAY/0AJK",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb420 sample oracle" {
  let bytes = jpeg_sample_fixture("rgb420")
  let expected = @base64.decode(
    "AAMAAgkCFwMpHgowIw0+KhRFNhJqOxdvWxCPWxCPcxqseSCycBHNhyjkjjCekzWjqCQNCA8IDhUOIw81KhY8LxlKNiBRQh52SCR8aR6dah+eeiGzgSi6hifjjS7qmTupiSuZtDAZBCoFCS8KFys2HjI9LDNFMjlLSDVvTTp0YjKgaTmndjmhfUConkDemjzavkO3oyict0gTEDYRFTsWJDhDKj5JOD9RPkVXVEF7WUaAbDyqd0e1hkmxik21pUflpUflxEm9tTquw1QfHkEjI0YoJ047LVRBPU9nQ1VtVlSFW1mKX2ChZmeob2jPcmvSjl7UmWnfpHQFo3MEt28nKk0vMFM1M1pHOWBNSVtzUGJ6YmCRZ2WWbG2ubm+wd3DXgXrhn2/lqnrwqXkKrHwNw3szEnMiF3gnIHs+J4JFO3tjQoJqVIB/WoaFX4ioZI2teYi/hJPKqJS3o4+ypJcLqJsPuZomHn8uI4QzLIdKM45RSIhwTo52YY2MZpKRa5S0dp+/h5bNjZzTsJy/l4OmrqEVtagcxaYyDp8qE6QvKZ9HMKZOQaJtR6hzUqyJV7GOarCycLa4h6jJj7DRrsKHma1ynrsRqMUbw7s0Gao1Hq86NatTO7FZTK14U7R/XbeUYryZdbu9e8HDmLnaosPkt8uQnLB1r8wircog0MhBHb48IsNBQrpYScFfT8GDVceJWc6iXtOndNC3d9O6jMzvmNj7ru1YmtlE0N4py9kkzd5AKstJL9BOUMhmVs5sXM6QYtSWZtuva+C0ftrBieXMnt7/nt7/pONOpONOxtQf4O452+xOGOk2Hu88RN5sS+VzTut6VfKBY++mafWsjfDTj/LVju/el/jnwfoNu/QHqxRJpxBF0AJM",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb_progressive sample oracle" {
  let bytes = jpeg_sample_fixture("rgb_progressive")
  let expected = @base64.decode(
    "AAMAAgkCFwMpHgowIw0+KhRFNhJqOxdvWxCPWxCPcxqseSCycBHNhyjkjjCekzWjqCQNCA8IDhUOIw81KhY8LxlKNiBRQh52SCR8aR6dah+eeiGzgSi6hifjjS7qmTupiSuZtDAZBCoFCS8KFys2HjI9LDNFMjlLSDVvTTp0YjKgaTmndjmhfUConkDemjzavkO3oyict0gTEDYRFTsWJDhDKj5JOD9RPkVXVEF7WUaAbDyqd0e1hkmxik21pUflpUflxEm9tTquw1QfHkEjI0YoJ047LVRBPU9nQ1VtVlSFW1mKX2ChZmeob2jPcmvSjl7UmWnfpHQFo3MEt28nKk0vMFM1M1pHOWBNSVtzUGJ6YmCRZ2WWbG2ubm+wd3DXgXrhn2/lqnrwqXkKrHwNw3szEnMiF3gnIHs+J4JFO3tjQoJqVIB/WoaFX4ioZI2teYi/hJPKqJS3o4+ypJcLqJsPuZomHn8uI4QzLIdKM45RSIhwTo52YY2MZpKRa5S0dp+/h5bNjZzTsJy/l4OmrqEVtagcxaYyDp8qE6QvKZ9HMKZOQaJtR6hzUqyJV7GOarCycLa4h6jJj7DRrsKHma1ynrsRqMUbw7s0Gao1Hq86NatTO7FZTK14U7R/XbeUYryZdbu9e8HDmLnaosPkt8uQnLB1r8wircog0MhBHb48IsNBQrpYScFfT8GDVceJWc6iXtOndNC3d9O6jMzvmNj7ru1YmtlE0N4py9kkzd5AKstJL9BOUMhmVs5sXM6QYtSWZtuva+C0ftrBieXMnt7/nt7/pONOpONOxtQf4O452+xOGOk2Hu88RN5sS+VzTut6VfKBY++mafWsjfDTj/LVju/el/jnwfoNu/QHqxRJpxBF0AJM",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb_progressive444 sample oracle" {
  let bytes = jpeg_sample_fixture("rgb_progressive444")
  let expected = @base64.decode(
    "AAACCgIRFwQkIgY2KghENQtVQg1pTA14WRCVXw6PdRa4fBy+dBDKkibSnxjxrxT/ryAQAhIHDhMWHBUpJxc7LRpIOR1aRx5tUh98XyWVZiWNcyihfCnDgyjnkTDYoyrpoD4AszIVBicKECgYHikrKSw9Mi9MPDBeSTNzVDSAXjaZajinczexfTy6jknYkzvxrUD1nUUXt0cZCToPEjsdIT0xKz5CNEFRPURhTEZ2VkaEXkiRb06peUfagFC+jVPmlU/lrEn8q10SuVkdDE0XFk0lJU85MFFKN1RYQVZpUFh9W1mLZGCVcV+zgGLGhGHViWDWoF//o3gAsG0FvGwlDl8aGmAqKGE+MGROOWddRGpvUmuCXWuQZ3Cpb260fXeliXTpknblqnn3oYEAs3cXv34qEXUfG3UtKXZANXlSPHtgRn5xVH+GYICVZ4aYcoDLfYmzjYzYmo/4o4D/qo4qvY0hw5MtFoYkIIYyLYhFOItXQY1mS492WpGLY5KYa5K7e56yhJfRjZjom5/okKoAraIVxaAbxqUyF5ooIpo2L5xJOp9dQ6JsTaN8W6aRZaaea6zAerKvhajOlKvhprPqproNqbQay7Ihx7k2G6ouJqo8NK1QPq5iR7FxUrSDX7aWabakf7W/eMLFkbzcl8T7qLn/q7oVrdARwL8pyctDHr8zKb9CN8BWQsNnScd2VMiHY8qbbcupicS+ctTIksvold7nqdTkttUNvectx9gyz91AIdI5K9RHOtZbRNdsTdp6V9yLZN+gb9+tdOC+eOrimurPneTmmfUKovUAsN4jyPo51PFJI+I8L+RKPeVeSOdwTup9WeyRZ+2kc++zifXBjvXKh+/umvT0p/8Jvu8awQs+0wAz0AJK",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb_restart sample oracle" {
  let bytes = jpeg_sample_fixture("rgb_restart")
  let expected = @base64.decode(
    "AAACCgIRFwQkIgY2KghENQtVQg1pTA14WRCVXw6PdRa4fBy+dBDKkibSnxjxrxT/ryAQAhIHDhMWHBUpJxc7LRpIOR1aRx5tUh98XyWVZiWNcyihfCnDgyjnkTDYoyrpoD4AszIVBicKECgYHikrKSw9Mi9MPDBeSTNzVDSAXjaZajinczexfTy6jknYkzvxrUD1nUUXt0cZCToPEjsdIT0xKz5CNEFRPURhTEZ2VkaEXkiRb06peUfagFC+jVPmlU/lrEn8q10SuVkdDE0XFk0lJU85MFFKN1RYQVZpUFh9W1mLZGCVcV+zgGLGhGHViWDWoF//o3gAsG0FvGwlDl8aGmAqKGE+MGROOWddRGpvUmuCXWuQZ3Cpb260fXeliXTpknblqnn3oYEAs3cXv34qEXUfG3UtKXZANXlSPHtgRn5xVH+GYICVZ4aYcoDLfYmzjYzYmo/4o4D/qo4qvY0hw5MtFoYkIIYyLYhFOItXQY1mS492WpGLY5KYa5K7e56yhJfRjZjom5/okKoAraIVxaAbxqUyF5ooIpo2L5xJOp9dQ6JsTaN8W6aRZaaea6zAerKvhajOlKvhprPqproNqbQay7Ihx7k2G6ouJqo8NK1QPq5iR7FxUrSDX7aWabakf7W/eMLFkbzcl8T7qLn/q7oVrdARwL8pyctDHr8zKb9CN8BWQsNnScd2VMiHY8qbbcupicS+ctTIksvold7nqdTkttUNvectx9gyz91AIdI5K9RHOtZbRNdsTdp6V9yLZN+gb9+tdOC+eOrimurPneTmmfUKovUAsN4jyPo51PFJI+I8L+RKPeVeSOdwTup9WeyRZ+2kc++zifXBjvXKh+/umvT0p/8Jvu8awQs+0wAz0AJK",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb_progressive_restart sample oracle" {
  let bytes = jpeg_sample_fixture("rgb_progressive_restart")
  let expected = @base64.decode(
    "AAACCgIRFwQkIgY2KghENQtVQg1pTA14WRCVXw6PdRa4fBy+dBDKkibSnxjxrxT/ryAQAhIHDhMWHBUpJxc7LRpIOR1aRx5tUh98XyWVZiWNcyihfCnDgyjnkTDYoyrpoD4AszIVBicKECgYHikrKSw9Mi9MPDBeSTNzVDSAXjaZajinczexfTy6jknYkzvxrUD1nUUXt0cZCToPEjsdIT0xKz5CNEFRPURhTEZ2VkaEXkiRb06peUfagFC+jVPmlU/lrEn8q10SuVkdDE0XFk0lJU85MFFKN1RYQVZpUFh9W1mLZGCVcV+zgGLGhGHViWDWoF//o3gAsG0FvGwlDl8aGmAqKGE+MGROOWddRGpvUmuCXWuQZ3Cpb260fXeliXTpknblqnn3oYEAs3cXv34qEXUfG3UtKXZANXlSPHtgRn5xVH+GYICVZ4aYcoDLfYmzjYzYmo/4o4D/qo4qvY0hw5MtFoYkIIYyLYhFOItXQY1mS492WpGLY5KYa5K7e56yhJfRjZjom5/okKoAraIVxaAbxqUyF5ooIpo2L5xJOp9dQ6JsTaN8W6aRZaaea6zAerKvhajOlKvhprPqproNqbQay7Ihx7k2G6ouJqo8NK1QPq5iR7FxUrSDX7aWabakf7W/eMLFkbzcl8T7qLn/q7oVrdARwL8pyctDHr8zKb9CN8BWQsNnScd2VMiHY8qbbcupicS+ctTIksvold7nqdTkttUNvectx9gyz91AIdI5K9RHOtZbRNdsTdp6V9yLZN+gb9+tdOC+eOrimurPneTmmfUKovUAsN4jyPo51PFJI+I8L+RKPeVeSOdwTup9WeyRZ+2kc++zifXBjvXKh+/umvT0p/8Jvu8awQs+0wAz0AJK",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG rgb_direct sample oracle" {
  let bytes = jpeg_sample_fixture("rgb_direct")
  let expected = @base64.decode(
    "AAABDAISFgQjIQYzLghFOApVQgxnTg54WBCJZBKWbxSqeRa4hhjPkBremhzyph78sSARAhMFDhUWGRcnIxk3MBtJOh1ZRB9rUCF7WiONZiWdcSe4eynFiCvLki3cnC/6qDEAszMVBicKESgbHCssJi09My5PPTBfSDNwUzSBXjeSaTiddDu7fj2+iz7UlUDqoEP9q0QRtkYaCTkPFDogHz0yKT9CNkBUQEJkS0V1VkaGYUmRbEqyd02rgU/TjlDdmFLso1X1rlYLuVgfDE0UF08lIlE2LFNGOVVYQ1dpTll6WVqLZF2ib1+uemG8hGPKkWXlm2f1pmkAsWoavG0kD18ZGmAqJWM7L2VLPGZdRmhuUWt/XGyQZ2+ic3CqfXPOh3XQlHbdnnjzqXsQtHwRv38pEnIfHnQvKHZBMnhRP3pjSXxzVH6FYICVaoKhdoS+gIa+iojdl4r0ooz3rI4LuJAbwpIuFIUjIIczKolFNYtVQY1nTI93VpGIYpOZbJWseJe+gpnNjZvcmZ3vpJ8ArqEUuqMixaUyGJkoJJs5Lp1KOJ9aRaBsT6J8WqWOZqaecaqyfKq+h6rVka7inrT6qLADsr0XvrMoybk4GqstJq0+MK9POrFgR7NyUbWCXLeTaLmkc7mwfsDDib7hk8buoLvxqsUCtMAvwMkly8k9Hb8yKcFDM8NUPsVkS8d2VcmGX8uYa82ods7Ggs3IjNfUltHpo9v/rd8TuNkXw+IwzuBCIdI3LNRIN9ZZQdhpTtp7WNyLY96dbuCueei4hePXj+LfmerypuAIsecVu/Ipx+w60e9HI+M8L+RNOedfQ+lvUOqBWuyRZe+icPCze+3Fh/PRkvzunPX1qf8Gs/8XvQAqyQU61AVM",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 3))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG gray sample oracle" {
  let bytes = jpeg_sample_fixture("gray")
  let expected = @base64.decode(
    "AAYNFBkgJyw1NUVLQ1pZXkkMEhkgJSwzOUNETFNZYGRUVRofJi0zOUFGTVRXXm5qdVpjJiszOT9FTVJXYmdrdXV7bG8zOEBGTFJaX2dudnl6hXZ1fD9FTFJYX2ZrdHZ+iIuWe36ITVJZYGVsc3l/hIqVnpmLj5ZZXmVscniAhYuWmJ6mjZWcomZrcnl/hY2Sm6GiqrWgn6mucXZ+hIqRmJ2mrLO9vqOwrrt/hIuSmJ6mq7K1vcnJtcXAx4yRmZ+lq7O4vMfPz7+/u9XVlpyjqq+2vcPP0dDZzshHQ0g=",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 1))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG gray_progressive sample oracle" {
  let bytes = jpeg_sample_fixture("gray_progressive")
  let expected = @base64.decode(
    "AAYNFBkgJyw1NUVLQ1pZXkkMEhkgJSwzOUNETFNZYGRUVRofJi0zOUFGTVRXXm5qdVpjJiszOT9FTVJXYmdrdXV7bG8zOEBGTFJaX2dudnl6hXZ1fD9FTFJYX2ZrdHZ+iIuWe36ITVJZYGVsc3l/hIqVnpmLj5ZZXmVscniAhYuWmJ6mjZWcomZrcnl/hY2Sm6GiqrWgn6mucXZ+hIqRmJ2mrLO9vqOwrrt/hIuSmJ6mq7K1vcnJtcXAx4yRmZ+lq7O4vMfPz7+/u9XVlpyjqq+2vcPP0dDZzshHQ0g=",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 1))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG cmyk sample oracle" {
  let bytes = jpeg_sample_fixture("cmyk")
  let expected = @base64.decode(
    "AAAB/wwCEv8WBCP/IQYz/y4IRf84ClX/Qgxn/04OeP9YEIn/ZBKW/28Uqv95Frj/hhjP/5Aa3v+aHPL/ph78/7EgEf8CEwX/DhUW/xkXJ/8jGTf/MBtJ/zodWf9EH2v/UCF7/1ojjf9mJZ3/cSe4/3spxf+IK8v/ki3c/5wv+v+oMQD/szMV/wYnCv8RKBv/HCss/yYtPf8zLk//PTBf/0gzcP9TNIH/XjeS/2k4nf90O7v/fj2+/4s+1P+VQOr/oEP9/6tEEf+2Rhr/CTkP/xQ6IP8fPTL/KT9C/zZAVP9AQmT/S0V1/1ZGhv9hSZH/bEqy/3dNq/+BT9P/jlDd/5hS7P+jVfX/rlYL/7lYH/8MTRT/F08l/yJRNv8sU0b/OVVY/0NXaf9OWXr/WVqL/2Rdov9vX67/emG8/4Rjyv+RZeX/m2f1/6ZpAP+xahr/vG0k/w9fGf8aYCr/JWM7/y9lS/88Zl3/Rmhu/1Frf/9cbJD/Z2+i/3Nwqv99c87/h3XQ/5R23f+eePP/qXsQ/7R8Ef+/fyn/EnIf/x50L/8odkH/MnhR/z96Y/9JfHP/VH6F/2CAlf9qgqH/doS+/4CGvv+KiN3/l4r0/6KM9/+sjgv/uJAb/8KSLv8UhSP/IIcz/yqJRf81i1X/QY1n/0yPd/9WkYj/YpOZ/2yVrP94l77/gpnN/42b3P+Zne//pJ8A/66hFP+6oyL/xaUy/xiZKP8kmzn/Lp1K/zifWv9FoGz/T6J8/1qljv9mpp7/caqy/3yqvv+HqtX/ka7i/560+v+osAP/sr0X/76zKP/JuTj/Gqst/yatPv8wr0//OrFg/0ezcv9RtYL/XLeT/2i5pP9zubD/fsDD/4m+4f+Txu7/oLvx/6rFAv+0wC//wMkl/8vJPf8dvzL/KcFD/zPDVP8+xWT/S8d2/1XJhv9fy5j/a82o/3bOxv+Czcj/jNfU/5bR6f+j2///rd8T/7jZF//D4jD/zuBC/yHSN/8s1Ej/N9ZZ/0HYaf9O2nv/WNyL/2Penf9u4K7/eei4/4Xj1/+P4t//mery/6bgCP+x5xX/u/Ip/8fsOv/R70f/I+M8/y/kTf8551//Q+lv/1Dqgf9a7JH/Ze+i/3Dws/977cX/h/PR/5L87v+c9fX/qf8G/7P/F/+9ACr/yQU6/9QFTP8=",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 4))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}

///|
test "JPEG cmyk_progressive sample oracle" {
  let bytes = jpeg_sample_fixture("cmyk_progressive")
  let expected = @base64.decode(
    "AAAB/wwCEv8WBCP/IQYz/y4IRf84ClX/Qgxn/04OeP9YEIn/ZBKW/28Uqv95Frj/hhjP/5Aa3v+aHPL/ph78/7EgEf8CEwX/DhUW/xkXJ/8jGTf/MBtJ/zodWf9EH2v/UCF7/1ojjf9mJZ3/cSe4/3spxf+IK8v/ki3c/5wv+v+oMQD/szMV/wYnCv8RKBv/HCss/yYtPf8zLk//PTBf/0gzcP9TNIH/XjeS/2k4nf90O7v/fj2+/4s+1P+VQOr/oEP9/6tEEf+2Rhr/CTkP/xQ6IP8fPTL/KT9C/zZAVP9AQmT/S0V1/1ZGhv9hSZH/bEqy/3dNq/+BT9P/jlDd/5hS7P+jVfX/rlYL/7lYH/8MTRT/F08l/yJRNv8sU0b/OVVY/0NXaf9OWXr/WVqL/2Rdov9vX67/emG8/4Rjyv+RZeX/m2f1/6ZpAP+xahr/vG0k/w9fGf8aYCr/JWM7/y9lS/88Zl3/Rmhu/1Frf/9cbJD/Z2+i/3Nwqv99c87/h3XQ/5R23f+eePP/qXsQ/7R8Ef+/fyn/EnIf/x50L/8odkH/MnhR/z96Y/9JfHP/VH6F/2CAlf9qgqH/doS+/4CGvv+KiN3/l4r0/6KM9/+sjgv/uJAb/8KSLv8UhSP/IIcz/yqJRf81i1X/QY1n/0yPd/9WkYj/YpOZ/2yVrP94l77/gpnN/42b3P+Zne//pJ8A/66hFP+6oyL/xaUy/xiZKP8kmzn/Lp1K/zifWv9FoGz/T6J8/1qljv9mpp7/caqy/3yqvv+HqtX/ka7i/560+v+osAP/sr0X/76zKP/JuTj/Gqst/yatPv8wr0//OrFg/0ezcv9RtYL/XLeT/2i5pP9zubD/fsDD/4m+4f+Txu7/oLvx/6rFAv+0wC//wMkl/8vJPf8dvzL/KcFD/zPDVP8+xWT/S8d2/1XJhv9fy5j/a82o/3bOxv+Czcj/jNfU/5bR6f+j2///rd8T/7jZF//D4jD/zuBC/yHSN/8s1Ej/N9ZZ/0HYaf9O2nv/WNyL/2Penf9u4K7/eei4/4Xj1/+P4t//mery/6bgCP+x5xX/u/Ip/8fsOv/R70f/I+M8/y/kTf8551//Q+lv/1Dqgf9a7JH/Ze+i/3Dws/977cX/h/PR/5L87v+c9fX/qf8G/7P/F/+9ACr/yQU6/9QFTP8=",
  )
  let actual = pdf_jpeg_decode(bytes, None)
  assert_eq((actual.width, actual.height, actual.components), (17, 13, 4))
  assert_eq(actual.bytes.length(), expected.length())
  let mut max_error = 0
  let mut sum_error = 0
  for i in 0..<expected.length() {
    let error = (actual.bytes[i].to_int() - expected[i].to_int()).abs()
    max_error = max_error.max(error)
    sum_error += error
  }
  assert_true(max_error <= 3, msg="max channel difference: \{max_error}")
  assert_true(
    sum_error <= expected.length(),
    msg="sum channel difference: \{sum_error}",
  )
}
